# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentAllocation, type: :model do
  describe "associations" do
    it { should belong_to(:payment) }
    it { should belong_to(:order) }
  end

  describe "validations" do
    it { should validate_presence_of(:amount) }
    it { should validate_numericality_of(:amount).is_greater_than(0) }
  end

  describe "order_belongs_to_payment_customer" do
    let!(:stock_location) { create(:stock_location) }
    let(:customer_a) { create(:customer, :with_credit) }
    let(:customer_b) { create(:customer, :with_credit) }
    let(:product) { create(:product, current_stock: 20, price_unit: 100) }

    let(:order_a) do
      Sales::CreateOrder.call(
        customer: customer_a,
        items: [ { product_id: product.id, quantity: 2, unit_price: 100 } ],
        order_type: "credit"
      ).record
    end

    let(:payment_a) { create(:payment, customer: customer_a) }

    it "is valid when order belongs to the payment customer" do
      allocation = build(:payment_allocation, payment: payment_a, order: order_a, amount: 100)
      expect(allocation).to be_valid
    end

    it "is invalid when order belongs to a different customer" do
      order_b = Sales::CreateOrder.call(
        customer: customer_b,
        items: [ { product_id: product.id, quantity: 1, unit_price: 100 } ],
        order_type: "credit"
      ).record

      allocation = build(:payment_allocation, payment: payment_a, order: order_b, amount: 50)
      expect(allocation).not_to be_valid
      expect(allocation.errors[:order]).to include("no pertenece al cliente del pago")
    end
  end

  describe "amount_within_order_outstanding_balance" do
    let!(:stock_location) { create(:stock_location) }
    let(:customer) { create(:customer, :with_credit) }
    let(:product) { create(:product, current_stock: 20, price_unit: 100) }
    let(:order) do
      Sales::CreateOrder.call(
        customer: customer,
        items: [ { product_id: product.id, quantity: 2, unit_price: 100 } ],
        order_type: "credit"
      ).record
    end
    let(:payment) { create(:payment, customer: customer, amount: 200) }

    it "is valid when amount equals exactly the remaining balance" do
      allocation = build(:payment_allocation, payment: payment, order: order, amount: 200)
      expect(allocation).to be_valid
    end

    it "is valid when amount is partial within remaining balance" do
      allocation = build(:payment_allocation, payment: payment, order: order, amount: 150)
      expect(allocation).to be_valid
    end

    it "is invalid when amount exceeds the order total (no other allocations)" do
      allocation = build(:payment_allocation, payment: payment, order: order, amount: 201)
      expect(allocation).not_to be_valid
      expect(allocation.errors[:amount].first).to match(/no puede exceder el saldo pendiente de la orden/)
    end

    context "when other allocations already exist for the same order" do
      let(:earlier_payment) { create(:payment, customer: customer, amount: 50) }
      before { create(:payment_allocation, payment: earlier_payment, order: order, amount: 50) }

      it "is valid when amount fits in the remaining balance" do
        allocation = build(:payment_allocation, payment: payment, order: order, amount: 150)
        expect(allocation).to be_valid
      end

      it "is invalid when amount exceeds the remaining balance" do
        allocation = build(:payment_allocation, payment: payment, order: order, amount: 151)
        expect(allocation).not_to be_valid
        expect(allocation.errors[:amount].first).to match(/no puede exceder el saldo pendiente de la orden/)
      end

      it "excludes itself on update (where.not(id: id))" do
        allocation = create(:payment_allocation, payment: payment, order: order, amount: 100)
        allocation.amount = 150
        expect(allocation).to be_valid
      end
    end
  end
end
