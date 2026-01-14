require 'rails_helper'

RSpec.describe OrderItem, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:order) }
    it { is_expected.to belong_to(:product) }
  end

  describe 'validations' do
    it 'validates quantity is greater than 0' do
      item = build(:order_item, quantity: 0)
      expect(item).not_to be_valid
      expect(item.errors[:quantity]).to be_present
    end

    it 'allows nil unit_price' do
      item = build(:order_item, unit_price: nil)
      expect(item).to be_valid
    end

    it 'allows zero unit_price' do
      item = build(:order_item, unit_price: 0)
      expect(item).to be_valid
    end

    it 'rejects negative unit_price' do
      item = build(:order_item, unit_price: -10)
      expect(item).not_to be_valid
      expect(item.errors[:unit_price]).to be_present
    end
  end
end
