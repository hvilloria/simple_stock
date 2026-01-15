require "rails_helper"

RSpec.describe Purchases::MarkAsPaid do
  let!(:supplier) { create(:supplier) }

  describe ".call" do
    context "with valid parameters" do
      let(:purchase) { create(:purchase, :simple_mode, status: "pending") }

      it "marks purchase as paid" do
        result = described_class.call(
          purchase: purchase,
          payment_date: Date.today
        )

        expect(result.success?).to be true
        expect(result.record.paid_status?).to be true
      end

      it "records payment date" do
        payment_date = Date.today + 1.day
        result = described_class.call(
          purchase: purchase,
          payment_date: payment_date
        )

        expect(result.success?).to be true
        expect(result.record.paid_at.to_date).to eq(payment_date)
      end

      it "defaults payment_date to today" do
        result = described_class.call(purchase: purchase)

        expect(result.success?).to be true
        expect(result.record.paid_at.to_date).to eq(Date.today)
      end

      it "returns the updated purchase record" do
        result = described_class.call(purchase: purchase)

        expect(result.record).to eq(purchase)
        expect(result.record).to be_persisted
      end
    end

    context "with invalid parameters" do
      it "fails if purchase is not in simple mode" do
        full_purchase = create(:purchase, :full_mode)
        
        result = described_class.call(purchase: full_purchase)

        expect(result.success?).to be false
        expect(result.errors).to include("Only simple mode purchases can be marked as paid")
      end

      it "fails if purchase is already paid" do
        paid_purchase = create(:purchase, :simple_mode, status: "paid")
        
        result = described_class.call(purchase: paid_purchase)

        expect(result.success?).to be false
        expect(result.errors).to include("Purchase is already paid")
      end

      it "fails if payment_date is before purchase_date" do
        purchase = create(:purchase, :simple_mode, status: "pending", purchase_date: Date.today)
        
        result = described_class.call(
          purchase: purchase,
          payment_date: 1.day.ago
        )

        expect(result.success?).to be false
        expect(result.errors).to include("Payment date cannot be before purchase date")
      end
    end

    context "does not change database on validation failure" do
      it "does not update status if validations fail" do
        full_purchase = create(:purchase, :full_mode)
        
        expect {
          described_class.call(purchase: full_purchase)
        }.not_to change { full_purchase.reload.status }
      end

      it "does not set paid_at if validations fail" do
        paid_purchase = create(:purchase, :simple_mode, status: "paid")
        
        expect {
          described_class.call(purchase: paid_purchase)
        }.not_to change { paid_purchase.reload.paid_at }
      end
    end
  end
end
