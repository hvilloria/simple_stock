require "rails_helper"

RSpec.describe Purchase, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:supplier) }
    it { is_expected.to have_many(:purchase_items).dependent(:destroy) }
    it { is_expected.to have_many(:products).through(:purchase_items) }
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:status).with_values(confirmed: "confirmed", cancelled: "cancelled").backed_by_column_of_type(:string).with_suffix }
  end

  describe "validations" do
    it { is_expected.to validate_inclusion_of(:currency).in_array(%w[USD ARS]) }

    context "when currency is USD" do
      subject { build(:purchase, currency: "USD") }

      it { is_expected.to validate_presence_of(:exchange_rate) }
      it { is_expected.to validate_numericality_of(:exchange_rate).is_greater_than(0) }
    end

    context "when currency is ARS" do
      subject { build(:purchase, :in_ars) }

      it "does not require exchange_rate" do
        purchase = build(:purchase, :in_ars, exchange_rate: nil)
        expect(purchase).to be_valid
      end
    end

    it { is_expected.to validate_presence_of(:purchase_date) }
  end

  describe "#calculate_total" do
    it "calculates total from purchase items" do
      purchase = create(:purchase)
      create(:purchase_item, purchase: purchase, quantity: 5, unit_cost: 10)
      create(:purchase_item, purchase: purchase, quantity: 3, unit_cost: 20)

      expect(purchase.calculate_total).to eq(110) # (5*10) + (3*20)
    end

    it "returns 0 when there are no items" do
      purchase = create(:purchase)
      expect(purchase.calculate_total).to eq(0)
    end
  end

  describe "#calculate_total_ars" do
    context "when currency is USD" do
      it "converts total to ARS using exchange rate" do
        purchase = create(:purchase, currency: "USD", exchange_rate: 1200)
        create(:purchase_item, purchase: purchase, quantity: 10, unit_cost: 50)

        # Total: 10 * 50 = 500 USD
        # In ARS: 500 * 1200 = 600000
        expect(purchase.calculate_total_ars).to eq(600000)
      end
    end

    context "when currency is ARS" do
      it "returns total without conversion" do
        purchase = create(:purchase, :in_ars)
        create(:purchase_item, purchase: purchase, quantity: 10, unit_cost: 5000)

        # Total: 10 * 5000 = 50000 ARS
        expect(purchase.calculate_total_ars).to eq(50000)
      end
    end
  end
end
