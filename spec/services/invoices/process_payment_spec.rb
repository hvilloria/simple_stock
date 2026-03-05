require "rails_helper"

RSpec.describe Invoices::ProcessPayment do
  let(:supplier) { create(:supplier) }
  let(:invoice)  { create(:invoice, :simple_mode, supplier: supplier, amount: 30_000) }

  describe ".call" do
    context "single invoice without credit applications" do
      it "marks the invoice as paid" do
        result = described_class.call(invoices: [ invoice ], payment_date: Date.today)

        expect(result.success?).to be true
        expect(invoice.reload.paid_status?).to be true
      end

      it "records the payment date" do
        payment_date = 2.days.from_now.to_date
        described_class.call(invoices: [ invoice ], payment_date: payment_date)

        expect(invoice.reload.paid_at.to_date).to eq(payment_date)
      end

      it "does not create any AppliedCredit records" do
        expect {
          described_class.call(invoices: [ invoice ])
        }.not_to change(AppliedCredit, :count)
      end
    end

    context "with credit applications" do
      let(:credit_note) { create(:credit_note, supplier: supplier, amount: 50_000) }

      it "creates an AppliedCredit record" do
        expect {
          described_class.call(
            invoices: [ invoice ],
            credit_applications: [
              { credit_note_id: credit_note.id, invoice_id: invoice.id, amount: 10_000 }
            ],
            payment_date: Date.today
          )
        }.to change(AppliedCredit, :count).by(1)
      end

      it "marks the invoice as paid after applying credits" do
        described_class.call(
          invoices: [ invoice ],
          credit_applications: [
            { credit_note_id: credit_note.id, invoice_id: invoice.id, amount: 10_000 }
          ],
          payment_date: Date.today
        )

        expect(invoice.reload.paid_status?).to be true
      end

      it "reduces the credit note remaining balance" do
        described_class.call(
          invoices: [ invoice ],
          credit_applications: [
            { credit_note_id: credit_note.id, invoice_id: invoice.id, amount: 10_000 }
          ],
          payment_date: Date.today
        )

        expect(credit_note.reload.remaining_balance).to eq(40_000)
      end

      it "allows applying more than the invoice amount (partial NC) leaving the remainder available" do
        small_invoice = create(:invoice, :simple_mode, supplier: supplier, amount: 5_000)

        described_class.call(
          invoices: [ small_invoice ],
          credit_applications: [
            { credit_note_id: credit_note.id, invoice_id: small_invoice.id, amount: 5_000 }
          ],
          payment_date: Date.today
        )

        expect(credit_note.reload.remaining_balance).to eq(45_000)
        expect(credit_note.reload.available?).to be true
      end

      it "allows applying to multiple invoices from the same credit note" do
        invoice2 = create(:invoice, :simple_mode, supplier: supplier, amount: 20_000)

        described_class.call(
          invoices: [ invoice, invoice2 ],
          credit_applications: [
            { credit_note_id: credit_note.id, invoice_id: invoice.id,  amount: 30_000 },
            { credit_note_id: credit_note.id, invoice_id: invoice2.id, amount: 20_000 }
          ],
          payment_date: Date.today
        )

        expect(credit_note.reload.remaining_balance).to eq(0)
        expect(invoice.reload.paid_status?).to be true
        expect(invoice2.reload.paid_status?).to be true
      end
    end

    context "with early payment discount" do
      let(:invoice_with_discount) do
        create(:invoice, :simple_mode,
               supplier: supplier,
               amount: 30_000,
               early_payment_due_date: 5.days.from_now.to_date,
               early_payment_discount_percentage: 5)
      end

      it "marks paid_with_discount automatically when discount is still valid" do
        described_class.call(
          invoices: [ invoice_with_discount ],
          payment_date: Date.today
        )

        expect(invoice_with_discount.reload.paid_with_discount).to be true
      end

      it "does not mark paid_with_discount when discount has expired" do
        expired_invoice = create(:invoice, :simple_mode,
                                 supplier: supplier,
                                 early_payment_due_date: 2.days.ago.to_date,
                                 early_payment_discount_percentage: 5)

        result = described_class.call(
          invoices: [ expired_invoice ],
          payment_date: Date.today
        )

        expect(result.success?).to be true
        expect(expired_invoice.reload.paid_with_discount).to be false
      end
    end

    context "validation failures" do
      it "fails when invoices list is empty" do
        result = described_class.call(invoices: [])
        expect(result.success?).to be false
        expect(result.errors.first).to match(/al menos una factura/i)
      end

      it "fails if invoice is already paid" do
        paid_invoice = create(:invoice, :simple_mode, supplier: supplier, status: "paid")

        result = described_class.call(invoices: [ paid_invoice ])
        expect(result.success?).to be false
        expect(result.errors.first).to match(/ya está pagada/i)
      end

      it "fails if invoice is not simple mode" do
        full_invoice = create(:invoice, :full_mode, supplier: supplier)

        result = described_class.call(invoices: [ full_invoice ])
        expect(result.success?).to be false
        expect(result.errors.first).to match(/modo simple/i)
      end

      it "fails if invoices belong to different suppliers" do
        other_supplier = create(:supplier)
        other_invoice = create(:invoice, :simple_mode, supplier: other_supplier)

        result = described_class.call(invoices: [ invoice, other_invoice ])
        expect(result.success?).to be false
        expect(result.errors.first).to match(/mismo proveedor/i)
      end

      it "fails if credit note belongs to a different supplier" do
        other_supplier = create(:supplier)
        foreign_cn = create(:credit_note, supplier: other_supplier, amount: 10_000)

        result = described_class.call(
          invoices: [ invoice ],
          credit_applications: [
            { credit_note_id: foreign_cn.id, invoice_id: invoice.id, amount: 5_000 }
          ]
        )

        expect(result.success?).to be false
        expect(result.errors.first).to match(/otro proveedor/i)
      end

      it "fails if credit application exceeds available balance" do
        cn = create(:credit_note, supplier: supplier, amount: 10_000)

        result = described_class.call(
          invoices: [ invoice ],
          credit_applications: [
            { credit_note_id: cn.id, invoice_id: invoice.id, amount: 15_000 }
          ]
        )

        expect(result.success?).to be false
        expect(result.errors.first).to match(/saldo disponible/i)
      end

      it "fails if credit note is not active (cancelled)" do
        cancelled_cn = create(:credit_note, :cancelled, supplier: supplier, amount: 10_000)

        result = described_class.call(
          invoices: [ invoice ],
          credit_applications: [
            { credit_note_id: cancelled_cn.id, invoice_id: invoice.id, amount: 5_000 }
          ]
        )

        expect(result.success?).to be false
        expect(result.errors.first).to match(/no está disponible/i)
      end

      it "fails if invoice in credit_applications is not in the invoices list" do
        cn = create(:credit_note, supplier: supplier, amount: 10_000)
        other_invoice = create(:invoice, :simple_mode, supplier: supplier)

        result = described_class.call(
          invoices: [ invoice ],
          credit_applications: [
            { credit_note_id: cn.id, invoice_id: other_invoice.id, amount: 5_000 }
          ]
        )

        expect(result.success?).to be false
      end
    end

    context "transactional safety" do
      it "does not mark invoices as paid if credit creation fails" do
        cn = create(:credit_note, supplier: supplier, amount: 10_000)

        allow(AppliedCredit).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)

        expect {
          described_class.call(
            invoices: [ invoice ],
            credit_applications: [
              { credit_note_id: cn.id, invoice_id: invoice.id, amount: 5_000 }
            ]
          )
        }.not_to change { invoice.reload.status }
      end
    end
  end
end
