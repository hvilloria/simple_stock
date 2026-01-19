require "rails_helper"

RSpec.describe InvoiceItem, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:invoice) }
    it { is_expected.to belong_to(:product) }
  end

  describe "validations" do
    it { is_expected.to validate_numericality_of(:quantity).is_greater_than(0) }
    it { is_expected.to validate_numericality_of(:unit_cost).is_greater_than_or_equal_to(0) }
  end

  describe "#unit_cost_ars" do
    context "when invoice currency is USD" do
      it "converts unit cost to ARS" do
        invoice = create(:invoice, currency: "USD", exchange_rate: 1200)
        item = create(:invoice_item, invoice: invoice, unit_cost: 50)

        expect(item.unit_cost_ars).to eq(60000) # 50 * 1200
      end
    end

    context "when invoice currency is ARS" do
      it "returns unit cost without conversion" do
        invoice = create(:invoice, :in_ars)
        item = create(:invoice_item, invoice: invoice, unit_cost: 5000)

        expect(item.unit_cost_ars).to eq(5000)
      end
    end
  end

  describe "#subtotal" do
    it "calculates subtotal in original currency" do
      item = build(:invoice_item, quantity: 5, unit_cost: 100)
      expect(item.subtotal).to eq(500)
    end
  end

  describe "#subtotal_ars" do
    context "when invoice currency is USD" do
      it "calculates subtotal in ARS" do
        invoice = create(:invoice, currency: "USD", exchange_rate: 1200)
        item = create(:invoice_item, invoice: invoice, quantity: 5, unit_cost: 50)

        # quantity * unit_cost * exchange_rate
        # 5 * 50 * 1200 = 300000
        expect(item.subtotal_ars).to eq(300000)
      end
    end

    context "when invoice currency is ARS" do
      it "calculates subtotal without conversion" do
        invoice = create(:invoice, :in_ars)
        item = create(:invoice_item, invoice: invoice, quantity: 5, unit_cost: 5000)

        expect(item.subtotal_ars).to eq(25000) # 5 * 5000
      end
    end
  end
end
