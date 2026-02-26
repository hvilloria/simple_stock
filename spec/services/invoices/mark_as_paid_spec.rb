require "rails_helper"

RSpec.describe Invoices::MarkAsPaid do
  let!(:supplier) { create(:supplier) }

  describe ".call" do
    context "with valid parameters" do
      let(:invoice) { create(:invoice, :simple_mode, status: "pending") }

      it "marks invoice as paid" do
        result = described_class.call(
          invoice: invoice,
          payment_date: Date.today
        )

        expect(result.success?).to be true
        expect(result.record.paid_status?).to be true
      end

      it "records payment date" do
        payment_date = Date.today + 1.day
        result = described_class.call(
          invoice: invoice,
          payment_date: payment_date
        )

        expect(result.success?).to be true
        expect(result.record.paid_at.to_date).to eq(payment_date)
      end

      it "defaults payment_date to today" do
        result = described_class.call(invoice: invoice)

        expect(result.success?).to be true
        expect(result.record.paid_at.to_date).to eq(Date.today)
      end

      it "returns the updated invoice record" do
        result = described_class.call(invoice: invoice)

        expect(result.record).to eq(invoice)
        expect(result.record).to be_persisted
      end

      it "does not automatically apply associated credit notes" do
        credit_note = create(:credit_note, supplier: invoice.supplier, invoice: invoice, status: "active")

        described_class.call(invoice: invoice, payment_date: Date.today)

        expect(credit_note.reload.active_status?).to be true
      end
    end

    context "with invalid parameters" do
      it "fails if invoice is not in simple mode" do
        full_invoice = create(:invoice, :full_mode)

        result = described_class.call(invoice: full_invoice)

        expect(result.success?).to be false
        expect(result.errors).to include("Only simple mode invoices can be marked as paid")
      end

      it "fails if invoice is already paid" do
        paid_invoice = create(:invoice, :simple_mode, status: "paid")

        result = described_class.call(invoice: paid_invoice)

        expect(result.success?).to be false
        expect(result.errors).to include("Invoice is already paid")
      end

      it "fails if payment_date is before purchase_date" do
        invoice = create(:invoice, :simple_mode, status: "pending", purchase_date: Date.current)

        result = described_class.call(
          invoice: invoice,
          payment_date: 1.day.ago.to_date
        )

        expect(result.success?).to be false
        expect(result.errors).to include("Payment date cannot be before invoice date")
      end
    end

    context "does not change database on validation failure" do
      it "does not update status if validations fail" do
        full_invoice = create(:invoice, :full_mode)

        expect {
          described_class.call(invoice: full_invoice)
        }.not_to change { full_invoice.reload.status }
      end

      it "does not set paid_at if validations fail" do
        paid_invoice = create(:invoice, :simple_mode, status: "paid")

        expect {
          described_class.call(invoice: paid_invoice)
        }.not_to change { paid_invoice.reload.paid_at }
      end
    end

    context "with early payment discount" do
      let(:invoice) do
        create(:invoice, :simple_mode,
              status: "pending",
              amount: 1000,
              early_payment_due_date: 5.days.from_now.to_date,
              early_payment_discount_percentage: 5)
      end

      it "marks invoice with discount applied when apply_discount is true" do
        result = described_class.call(
          invoice: invoice,
          payment_date: Date.today,
          apply_discount: true
        )

        expect(result.success?).to be true
        expect(result.record.paid_with_discount).to be true
      end

      it "marks invoice without discount when apply_discount is false" do
        result = described_class.call(
          invoice: invoice,
          payment_date: Date.today,
          apply_discount: false
        )

        expect(result.success?).to be true
        expect(result.record.paid_with_discount).to be false
      end

      it "defaults apply_discount to false" do
        result = described_class.call(
          invoice: invoice,
          payment_date: Date.today
        )

        expect(result.success?).to be true
        expect(result.record.paid_with_discount).to be false
      end

      it "fails when applying expired discount" do
        invoice_expired = create(:invoice, :simple_mode,
                                status: "pending",
                                early_payment_due_date: 2.days.ago.to_date,
                                early_payment_discount_percentage: 5)

        result = described_class.call(
          invoice: invoice_expired,
          payment_date: Date.current,
          apply_discount: true
        )

        expect(result.success?).to be false
        expect(result.errors).to include("Discount has expired or is not available for this invoice")
      end

      it "fails when payment date is after discount expiration" do
        result = described_class.call(
          invoice: invoice,
          payment_date: invoice.early_payment_due_date + 1.day,
          apply_discount: true
        )

        expect(result.success?).to be false
        expect(result.errors).to include("Discount has expired or is not available for this invoice")
      end
    end
  end
end
