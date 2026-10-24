require "rails_helper"

RSpec.describe PaymentsHelper, type: :helper do
  describe "#payment_allocation_discount_percent" do
    def percent_for(amount, discount)
      helper.payment_allocation_discount_percent(build(:payment_allocation, amount: amount, discount_amount: discount))
    end

    it "snaps a partial cash collection's discount to the allowed percent" do
      expect(percent_for(250_000, 25_000)).to eq(10)
    end

    it "snaps a settling cash collection's discount to the allowed percent" do
      expect(percent_for(228_800, 28_200)).to eq(10)
    end

    it "reads an old grossed-up discount as the allowed percent" do
      expect(percent_for(250_000, 27_778)).to eq(10)
    end

    it "snaps a small discount to the lower allowed percent" do
      expect(percent_for(100_000, 5_000)).to eq(5)
    end

    it "is nil without a discount" do
      expect(percent_for(100_000, 0)).to be_nil
    end
  end
end
