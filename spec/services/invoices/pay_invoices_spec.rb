# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::PayInvoices do
  let(:user)     { create(:user, :admin) }
  let(:supplier) { create(:supplier, name: "Sergio Sussex", expense_types: %w[supplier taxes]) }
  let(:afip)     { create(:supplier, name: "AFIP", expense_types: %w[supplier taxes social_charges utilities]) }

  def pending_invoice(supplier:, amount:, number:, **attrs)
    create(:invoice, :simple_mode, :in_ars, supplier: supplier, amount: amount,
           invoice_number: number, purchase_date: Date.current - 10, **attrs)
  end

  def pay(invoices, account: "main_cash", payment_date: Date.current, credit_note_ids: [])
    described_class.call(invoices: invoices, account: account, payment_date: payment_date,
                         user: user, credit_note_ids: credit_note_ids)
  end

  describe "a single tax invoice" do
    let(:invoice) { pending_invoice(supplier: afip, amount: 250_000, number: "IIBB 09/2026", expense_type: "taxes") }

    it "writes one fixed-expense outflow from the chosen arca and links it" do
      result = pay([ invoice ])

      expect(result.success?).to be true
      movement = result.record
      expect(movement).to have_attributes(account: "main_cash", amount: -250_000, category: "fixed_expense",
                                          subcategory: "taxes", business_date: Date.current, user: user,
                                          description: "Pago AFIP — IIBB 09/2026")
      expect(invoice.reload).to have_attributes(status: "paid", cash_movement_id: movement.id)
      expect(invoice.paid_at.to_date).to eq(Date.current)
      expect(movement.automatic?).to be true
    end
  end

  describe "a batch of supplier invoices with a credit note" do
    let!(:first)  { pending_invoice(supplier: supplier, amount: 100_000, number: "SF 2509") }
    let!(:second) { pending_invoice(supplier: supplier, amount: 80_000, number: "SF 2510") }
    let!(:third)  { pending_invoice(supplier: supplier, amount: 50_000, number: "SF 2511") }
    let!(:credit) { create(:credit_note, supplier: supplier, amount: 30_000) }

    it "writes one supplier outflow for the net from the drawer" do
      result = nil
      expect {
        result = pay([ first, second, third ], account: "drawer", credit_note_ids: [ credit.id ])
      }.to change(CashMovement, :count).by(1).and change(AppliedCredit, :count).by(1)

      expect(result.record).to have_attributes(account: "drawer", amount: -200_000, category: "suppliers",
                                               subcategory: nil,
                                               description: "Pago Sergio Sussex — SF 2509, SF 2510, SF 2511")
      expect([ first, second, third ].map { |i| i.reload.cash_movement_id }.uniq).to eq([ result.record.id ])
      expect(credit.reload.remaining_balance).to eq(0)
    end
  end

  it "pays a USD invoice in pesos at its exchange rate" do
    invoice = create(:invoice, :simple_mode, supplier: supplier, currency: "USD", exchange_rate: 1200,
                     amount: 1000, purchase_date: Date.current - 10)
    expect(pay([ invoice ], account: "bank").record.amount).to eq(-1_200_000)
  end

  it "applies the early-payment discount within its deadline and not after it" do
    on_time = pending_invoice(supplier: supplier, amount: 100_000, number: "A",
                              early_payment_due_date: Date.current, early_payment_discount_percentage: 5)
    late = pending_invoice(supplier: supplier, amount: 100_000, number: "B",
                           early_payment_due_date: Date.current - 1, early_payment_discount_percentage: 5)

    expect(pay([ on_time ]).record.amount).to eq(-95_000)
    expect(on_time.reload.paid_with_discount).to be true
    expect(pay([ late ]).record.amount).to eq(-100_000)
    expect(late.reload.paid_with_discount).to be false
  end

  it "caps a credit at the USD invoice's peso amount due" do
    invoice = create(:invoice, :simple_mode, supplier: supplier, currency: "USD", exchange_rate: 1000,
                     amount: 100, purchase_date: Date.current - 10,
                     early_payment_due_date: Date.current, early_payment_discount_percentage: 10)
    credit = create(:credit_note, supplier: supplier, amount: 30_000)

    result = pay([ invoice ], credit_note_ids: [ credit.id ])

    expect(result.record.amount).to eq(-60_000)
    expect(AppliedCredit.last.amount).to eq(30_000)
  end

  it "converts a USD credit note into pesos against a USD invoice" do
    invoice = create(:invoice, :simple_mode, supplier: supplier, currency: "USD", exchange_rate: 1200,
                     amount: 1000, purchase_date: Date.current - 10)
    credit = create(:credit_note, :usd, supplier: supplier, amount: 100, exchange_rate: 1200)

    result = pay([ invoice ], credit_note_ids: [ credit.id ])

    expect(result.record.amount).to eq(-1_080_000)
    expect(AppliedCredit.last.amount).to eq(100)
    expect(credit.reload.remaining_balance).to eq(0)
  end

  it "applies a USD credit note to an ARS invoice at the note's rate" do
    invoice = pending_invoice(supplier: supplier, amount: 200_000, number: "SF 3")
    credit  = create(:credit_note, :usd, supplier: supplier, amount: 100, exchange_rate: 1000)

    result = pay([ invoice ], credit_note_ids: [ credit.id ])

    expect(result.record.amount).to eq(-100_000)
    expect(AppliedCredit.last.amount).to eq(100)
  end

  describe "a USD credit note that covers an ARS invoice" do
    it "writes no outflow when the note rounds to the whole invoice" do
      invoice = pending_invoice(supplier: supplier, amount: 1_000, number: "U1")
      credit  = create(:credit_note, :usd, supplier: supplier, amount: 1, exchange_rate: 1200)

      result = nil
      expect { result = pay([ invoice ], credit_note_ids: [ credit.id ]) }.not_to change(CashMovement, :count)

      expect(result.success?).to be true
      expect(invoice.reload).to have_attributes(status: "paid", cash_movement_id: nil)
      expect(AppliedCredit.last.amount).to eq(BigDecimal("0.84"))
      expect(credit.reload.remaining_balance).to eq(BigDecimal("0.16"))
    end

    it "writes no outflow for an amount that does not divide by the rate" do
      invoice = pending_invoice(supplier: supplier, amount: 123_457, number: "U2")
      credit  = create(:credit_note, :usd, supplier: supplier, amount: 103, exchange_rate: 1200)

      expect { pay([ invoice ], credit_note_ids: [ credit.id ]) }.not_to change(CashMovement, :count)
      expect(invoice.reload.status).to eq("paid")
    end

    it "spreads one note across two invoices and pays only the rest in cash" do
      first  = pending_invoice(supplier: supplier, amount: 1_000, number: "U3")
      second = pending_invoice(supplier: supplier, amount: 1_500, number: "U4")
      credit = create(:credit_note, :usd, supplier: supplier, amount: 2, exchange_rate: 1200)

      result = pay([ first, second ], credit_note_ids: [ credit.id ])

      expect(AppliedCredit.order(:id).pluck(:amount)).to eq([ BigDecimal("0.84"), BigDecimal("1.16") ])
      expect(credit.reload.remaining_balance).to eq(0)
      expect(result.record.amount).to eq(-108)
    end
  end

  it "marks the invoices paid without an outflow when credits cover everything" do
    invoice = pending_invoice(supplier: supplier, amount: 20_000, number: "SF 1")
    credit  = create(:credit_note, supplier: supplier, amount: 50_000)

    result = nil
    expect { result = pay([ invoice ], credit_note_ids: [ credit.id ]) }.not_to change(CashMovement, :count)
    expect(result.success?).to be true
    expect(result.record).to be_nil
    expect(invoice.reload).to have_attributes(status: "paid", cash_movement_id: nil)
  end

  it "spends one credit note across several invoices and leaves the rest available" do
    first  = pending_invoice(supplier: supplier, amount: 10_000, number: "N1")
    second = pending_invoice(supplier: supplier, amount: 10_000, number: "N2")
    credit = create(:credit_note, supplier: supplier, amount: 15_000)

    result = pay([ first, second ], credit_note_ids: [ credit.id ])

    expect(result.record.amount).to eq(-5_000)
    expect(credit.reload.remaining_balance).to eq(0)

    other_credit = create(:credit_note, supplier: supplier, amount: 50_000)
    third = pending_invoice(supplier: supplier, amount: 20_000, number: "N3")
    pay([ third ], credit_note_ids: [ other_credit.id ])
    expect(other_credit.reload.remaining_balance).to eq(30_000)
  end

  it "refuses a credit note from another supplier" do
    invoice = pending_invoice(supplier: supplier, amount: 10_000, number: "SF 7")
    credit  = create(:credit_note, supplier: afip, amount: 1_000)
    result  = pay([ invoice ], credit_note_ids: [ credit.id ])
    expect(result.errors).to include("La nota de crédito #{credit.credit_note_number} pertenece a otro proveedor")
  end

  it "refuses an itemized (full mode) invoice" do
    invoice = create(:invoice, :full_mode, supplier: supplier, status: "pending", invoice_number: "FULL-1")
    result  = pay([ invoice ])
    expect(result.success?).to be false
    expect(result.errors).to include("Solo facturas en modo simple pueden pagarse (FULL-1)")
  end

  describe "refusals write nothing" do
    let(:invoice) { pending_invoice(supplier: supplier, amount: 10_000, number: "SF 9") }

    def expect_refusal(message, &block)
      result = nil
      expect { result = block.call }.not_to change(CashMovement, :count)
      expect(result.success?).to be false
      expect(result.errors).to include(message)
    end

    it "refuses a missing or unknown arca" do
      [ nil, "", "usd", "change_fund" ].each do |account|
        expect_refusal("Elegí de dónde sale la plata") { pay([ invoice ], account: account) }
      end
      expect(invoice.reload.pending_status?).to be true
    end

    it "refuses a closed day" do
      create(:daily_closing, business_date: Date.current - 1)
      expect_refusal("El día #{(Date.current - 1).strftime('%d/%m/%Y')} está cerrado. Usá una fecha abierta.") do
        pay([ invoice ], payment_date: Date.current - 1)
      end
    end

    it "refuses a future date" do
      expect_refusal("La fecha de pago no puede ser futura") { pay([ invoice ], payment_date: Date.current + 1) }
    end

    it "refuses a date before the invoice date" do
      expect_refusal("La fecha de pago no puede ser anterior a la fecha de la factura SF 9") do
        pay([ invoice ], payment_date: Date.current - 11)
      end
    end

    it "refuses mixed types" do
      taxes = pending_invoice(supplier: supplier, amount: 5_000, number: "X", expense_type: "taxes")
      expect_refusal("Pagá por separado las facturas de distinto tipo") { pay([ invoice, taxes ]) }
    end

    it "refuses mixed suppliers" do
      other = pending_invoice(supplier: afip, amount: 5_000, number: "Y")
      expect_refusal("Todas las facturas deben ser del mismo proveedor") { pay([ invoice, other ]) }
    end

    it "refuses credit notes on a non-supplier invoice" do
      taxes  = pending_invoice(supplier: afip, amount: 5_000, number: "Z", expense_type: "taxes")
      credit = create(:credit_note, supplier: afip, amount: 1_000)
      expect_refusal("Las notas de crédito solo se aplican a facturas de proveedor") do
        pay([ taxes ], credit_note_ids: [ credit.id ])
      end
    end

    it "refuses a cancelled or exhausted credit note" do
      cancelled = create(:credit_note, :cancelled, supplier: supplier, amount: 1_000)
      spent     = create(:credit_note, supplier: supplier, amount: 1_000)
      create(:applied_credit, credit_note: spent, invoice: pending_invoice(supplier: supplier, amount: 5_000, number: "P"),
                              amount: 1_000)

      [ cancelled, spent ].each do |credit|
        expect_refusal("La nota de crédito #{credit.credit_note_number} no está disponible") do
          pay([ invoice ], credit_note_ids: [ credit.id ])
        end
      end
    end

    it "refuses an unknown credit note" do
      expect_refusal("Nota de crédito no encontrada") { pay([ invoice ], credit_note_ids: [ 0, 999_999 ]) }
    end

    it "refuses an invoice that is not pending" do
      cancelled = pending_invoice(supplier: supplier, amount: 5_000, number: "CAN", status: "cancelled")
      expect_refusal("La factura CAN no está pendiente") { pay([ cancelled ]) }
    end

    it "refuses an empty list" do
      expect_refusal("Debe haber al menos una factura para pagar") { pay([]) }
    end

    it "pays only once on a double submit" do
      expect(pay([ invoice ]).success?).to be true
      expect_refusal("La factura SF 9 ya está pagada") { pay([ invoice ]) }
    end

    it "rolls back when the cash row cannot be written" do
      credit = create(:credit_note, supplier: supplier, amount: 1_000)
      allow(Cash::RecordMovement).to receive(:call).and_return(Result.new(success?: false, record: nil, errors: [ "boom" ]))

      expect { expect_refusal("boom") { pay([ invoice ], credit_note_ids: [ credit.id ]) } }
        .not_to change(AppliedCredit, :count)
      expect(invoice.reload.pending_status?).to be true
    end
  end
end
