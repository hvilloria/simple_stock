# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payment, type: :model do
  describe "associations" do
    it { should belong_to(:customer) }
    it { should have_many(:allocations).class_name("PaymentAllocation") }
    it { should have_many(:orders).through(:allocations) }
  end

  describe "validations" do
    it { should validate_presence_of(:amount) }
    it { should validate_numericality_of(:amount).is_greater_than(0) }
    it { should validate_presence_of(:payment_method) }
    it { should validate_inclusion_of(:payment_method).in_array(Payment::PAYMENT_METHODS) }
    it { should validate_presence_of(:payment_date) }

    context "for a customer without a credit account (retail / mostrador)" do
      let(:retail) { create(:customer, customer_type: "retail", has_credit_account: false) }

      it "is persisted successfully" do
        expect {
          create(:payment, customer: retail, amount: 100, payment_method: "cash", payment_date: Date.current)
        }.to change(Payment, :count).by(1)
      end
    end
  end

  describe "scopes" do
    let(:customer1) { create(:customer, customer_type: "workshop", has_credit_account: true) }
    let(:customer2) { create(:customer, customer_type: "workshop", has_credit_account: true) }
    let!(:payment1) { create(:payment, customer: customer1, payment_date: 3.days.ago) }
    let!(:payment2) { create(:payment, customer: customer2, payment_date: 1.day.ago) }
    let!(:payment3) { create(:payment, customer: customer1, payment_date: Date.current) }

    describe ".by_customer" do
      it "returns payments for specified customer" do
        expect(Payment.by_customer(customer1)).to contain_exactly(payment1, payment3)
      end
    end

    describe ".recent" do
      it "orders payments by payment_date desc, then created_at desc" do
        expect(Payment.recent).to eq([ payment3, payment2, payment1 ])
      end
    end
  end

  describe "factory" do
    it "has a valid default factory" do
      expect(create(:payment)).to be_valid
    end

    it "has a :bank_qr trait" do
      expect(create(:payment, :bank_qr).payment_method).to eq("bank_qr")
    end

    it "has a :bank_card trait" do
      expect(create(:payment, :bank_card).payment_method).to eq("bank_card")
    end

    it "has a :bank_transfer trait" do
      expect(create(:payment, :bank_transfer).payment_method).to eq("bank_transfer")
    end

    it "has a :mercado_pago trait" do
      expect(create(:payment, :mercado_pago).payment_method).to eq("mercado_pago")
    end
  end

  describe "payment method catalog" do
    it "defines exactly the five official methods" do
      expect(Payment::PAYMENT_METHODS).to eq(%w[cash bank_qr bank_card bank_transfer mercado_pago])
    end

    it "keeps 'cash' as the discount anchor key" do
      expect(Payment::PAYMENT_METHODS).to include("cash")
    end

    describe ".method_label" do
      it "returns the human label for a known key" do
        expect(Payment.method_label("bank_card")).to eq("Banco Tarjeta")
        expect(Payment.method_label("mercado_pago")).to eq("Mercado Pago")
      end

      it "humanizes an unknown key as a fallback" do
        expect(Payment.method_label("foo_bar")).to eq("Foo bar")
      end
    end

    describe ".method_options" do
      it "returns [label, key] pairs in catalog order for selects" do
        expect(Payment.method_options).to eq([
          [ "Efectivo", "cash" ],
          [ "Banco QR", "bank_qr" ],
          [ "Banco Tarjeta", "bank_card" ],
          [ "Banco Transferencia", "bank_transfer" ],
          [ "Mercado Pago", "mercado_pago" ]
        ])
      end
    end
  end

  describe "invoice" do
    it "is unbilled when born" do
      payment = create(:payment)

      expect(payment).not_to be_billed
      expect(payment.invoice_label).to be_nil
    end

    it "accepts A or B with a number" do
      expect(build(:payment, invoice_type: "b", invoice_number: "1452")).to be_valid
    end

    it "requires a number for A or B" do
      payment = build(:payment, invoice_type: "a", invoice_number: nil)

      expect(payment).not_to be_valid
      expect(payment.errors[:invoice_number]).to include("es obligatorio para facturas tipo A o B")
    end

    it "refuses a number on a payment marked with no invoice" do
      payment = build(:payment, invoice_type: "none", invoice_number: "1452")

      expect(payment).not_to be_valid
      expect(payment.errors[:invoice_number]).to include("debe estar vacío cuando no hay factura")
    end

    it "refuses a number with no invoice type" do
      payment = build(:payment, invoice_type: nil, invoice_number: "1452")

      expect(payment).not_to be_valid
      expect(payment.errors[:invoice_type]).to include("debe indicarse antes de cargar un número de factura")
    end

    it "labels what was billed" do
      expect(build(:payment, :invoice_b, invoice_number: "1452").invoice_label).to eq("Factura B · 1452")
      expect(build(:payment, :no_invoice).invoice_label).to eq("Sin factura")
    end
  end

  describe "cash movements" do
    let(:payment) { create(:payment) }

    it "knows its original movement and its reversal" do
      original = create(:cash_movement, source_payment: payment, amount: 10_000)
      reversal = create(:cash_movement, source_payment: payment, amount: -10_000)

      expect(payment.cash_movements).to eq([ original, reversal ])
      expect(payment.original_cash_movement).to eq(original)
      expect(payment.reversal_movement).to eq(reversal)
    end

    it "has none when it predates the cash module" do
      expect(payment.original_cash_movement).to be_nil
      expect(payment.reversal_movement).to be_nil
    end
  end

  describe "#cash_discounted?" do
    let(:payment) { create(:payment, payment_method: "cash", amount: 900) }

    it "is false for a plain cash collection" do
      order = create(:order, :pending, customer: payment.customer, order_type: "immediate", total_amount: 900, original_total_amount: 900)
      create(:order_item, order: order, quantity: 1, unit_price: 900, discount_percent: 0)
      create(:payment_allocation, payment: payment, order: order, amount: 900)

      expect(payment.cash_discounted?).to be(false)
    end

    it "is true when an immediate sale note carried the cash discount" do
      order = create(:order, :pending, customer: payment.customer, order_type: "immediate", total_amount: 900, original_total_amount: 1000)
      create(:order_item, order: order, quantity: 1, unit_price: 1000, discount_percent: 10)
      create(:payment_allocation, payment: payment, order: order, amount: 900)

      expect(payment.cash_discounted?).to be(true)
    end

    it "is true when an on-account collection carried a cash discount" do
      order = create(:order, :on_account, customer: payment.customer, total_amount: 1000, original_total_amount: 1000)
      create(:payment_allocation, payment: payment, order: order, amount: 900, discount_amount: 100)

      expect(payment.cash_discounted?).to be(true)
    end

    it "is true when cash was collected above the total" do
      order = create(:order, :on_account, customer: payment.customer, total_amount: 950, original_total_amount: 950)
      create(:payment_allocation, payment: payment, order: order, amount: 950, overpaid_amount: 50)

      expect(payment.cash_discounted?).to be(true)
    end

    it "ignores credit item discounts, which are not cash-only" do
      order = create(:order, :credit_order, customer: payment.customer, total_amount: 900, original_total_amount: 1000)
      create(:order_item, order: order, quantity: 1, unit_price: 1000, discount_percent: 10)
      create(:payment_allocation, payment: payment, order: order, amount: 900)

      expect(payment.cash_discounted?).to be(false)
    end

    it "is false for a non-cash payment" do
      payment.update!(payment_method: "mercado_pago")
      order = create(:order, :on_account, customer: payment.customer, total_amount: 1000, original_total_amount: 1000)
      create(:payment_allocation, payment: payment, order: order, amount: 900, discount_amount: 100)

      expect(payment.cash_discounted?).to be(false)
    end
  end

  describe "#method_change_block" do
    let(:date) { Date.new(2026, 10, 1) }
    let(:payment) { create(:payment, payment_method: "cash", amount: 900, payment_date: date) }

    def collect!
      create(:cash_movement, source_payment: payment, business_date: date, amount: 900)
    end

    it "is nil for a collection on an open day" do
      collect!

      expect(payment.method_change_block).to be_nil
    end

    it "is :locked without a cash movement" do
      expect(payment.method_change_block).to eq(:locked)
    end

    it "is :locked once reversed" do
      collect!
      create(:cash_movement, source_payment: payment, business_date: date, amount: -900)

      expect(payment.reload.method_change_block).to eq(:locked)
    end

    it "is :closed when the day has a closing" do
      collect!
      create(:daily_closing, business_date: date)

      expect(payment.method_change_block).to eq(:closed)
    end

    it "is :closed when the movement is sealed" do
      create(:cash_movement, :sealed, source_payment: payment, business_date: date, amount: 900)

      expect(payment.method_change_block).to eq(:closed)
    end

    it "is :cash_discount for a cash collection with a cash discount" do
      collect!
      order = create(:order, :on_account, customer: payment.customer, total_amount: 1000, original_total_amount: 1000)
      create(:payment_allocation, payment: payment, order: order, amount: 900, discount_amount: 100)

      expect(payment.method_change_block).to eq(:cash_discount)
    end
  end
end
