require "rails_helper"

RSpec.describe CreditNoteItem, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:credit_note) }
    it { is_expected.to belong_to(:product) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:quantity) }
    it { is_expected.to validate_numericality_of(:quantity).only_integer.is_greater_than(0) }
    it { is_expected.to validate_presence_of(:unit_price) }
    it { is_expected.to validate_numericality_of(:unit_price).is_greater_than_or_equal_to(0) }
  end

  describe "#total_price" do
    it "calculates total from quantity and unit_price" do
      item = build(:credit_note_item, quantity: 5, unit_price: 100)
      expect(item.total_price).to eq(500)
    end

    it "handles decimal unit_price" do
      item = build(:credit_note_item, quantity: 3, unit_price: 125.50)
      expect(item.total_price).to eq(376.50)
    end
  end
end
