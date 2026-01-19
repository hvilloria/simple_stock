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
        invoice = create(:invoice, :simple_mode, status: "pending", purchase_date: Date.today)

        result = described_class.call(
          invoice: invoice,
          payment_date: 1.day.ago
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
  end
end
