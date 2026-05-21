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

  describe "discount_percent" do
    let(:customer) { Customer.create!(name: "Test", customer_type: "retail") }
    let(:credit_customer) { Customer.create!(name: "Cred", customer_type: "workshop", has_credit_account: true) }
    let(:product) { Product.create!(sku: "X-1", name: "P", price_unit: 100, cost_unit: 50, cost_currency: "ARS") }

    def build_item(order:, percent:)
      OrderItem.new(order: order, product: product, quantity: 1, unit_price: 100, discount_percent: percent)
    end

    let(:immediate_order) do
      Order.create!(customer: customer, order_type: "immediate", source: "live",
                    sale_date: Date.today, total_amount: 100, original_total_amount: 100, status: "confirmed")
    end

    let(:credit_order) do
      Order.create!(customer: credit_customer, order_type: "credit", source: "live",
                    sale_date: Date.today, total_amount: 100, original_total_amount: 100, status: "confirmed")
    end

    it "is invalid with discount_percent < 0" do
      item = build_item(order: immediate_order, percent: -1)
      expect(item).not_to be_valid
      expect(item.errors[:discount_percent]).to be_present
    end

    it "is invalid with discount_percent > 20" do
      item = build_item(order: immediate_order, percent: 25)
      expect(item).not_to be_valid
      expect(item.errors[:discount_percent]).to be_present
    end

    it "is invalid with discount_percent > 10 when order is immediate" do
      item = build_item(order: immediate_order, percent: 15)
      expect(item).not_to be_valid
      expect(item.errors[:discount_percent]).to be_present
    end

    it "is invalid with discount_percent > 0 when order is credit" do
      item = build_item(order: credit_order, percent: 5)
      expect(item).not_to be_valid
      expect(item.errors[:discount_percent]).to be_present
    end

    it "is valid with discount_percent = 10 when order is immediate" do
      item = build_item(order: immediate_order, percent: 10)
      expect(item).to be_valid
    end

    it "is valid with discount_percent = 0 in any order_type" do
      expect(build_item(order: immediate_order, percent: 0)).to be_valid
      expect(build_item(order: credit_order, percent: 0)).to be_valid
    end
  end
end
