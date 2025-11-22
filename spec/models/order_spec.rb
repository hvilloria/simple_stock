require 'rails_helper'

RSpec.describe Order, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:customer).optional }
    it { is_expected.to have_many(:order_items).dependent(:destroy) }
  end

  describe 'enums' do
    it { is_expected.to define_enum_for(:status).with_values(confirmed: 'confirmed', cancelled: 'cancelled').backed_by_column_of_type(:string).with_suffix }
    it { is_expected.to define_enum_for(:order_type).with_values(cash: 'cash', credit: 'credit').backed_by_column_of_type(:string).with_suffix }
  end

  describe 'validations' do
    subject { build(:order) }

    it { is_expected.to validate_presence_of(:order_type) }
    it { is_expected.to validate_numericality_of(:total_amount).is_greater_than(0) }

    describe 'channel validation' do
      it 'allows nil channel' do
        order = build(:order, channel: nil)
        expect(order).to be_valid
      end

      it 'allows valid channels' do
        %w[counter whatsapp mercadolibre].each do |channel|
          order = build(:order, channel: channel)
          expect(order).to be_valid
        end
      end

      it 'rejects invalid channels' do
        order = build(:order, channel: 'invalid_channel')
        expect(order).not_to be_valid
        expect(order.errors[:channel]).to be_present
      end
    end

    describe 'credit_order_requires_credit_account' do
      context 'when order_type is cash' do
        it 'is valid even if customer does not have credit account' do
          customer = create(:customer, has_credit_account: false)
          order = build(:order, order_type: 'cash', customer: customer)
          expect(order).to be_valid
        end
      end

      context 'when order_type is credit' do
        it 'is valid if customer has credit account' do
          customer = create(:customer, has_credit_account: true)
          order = build(:order, order_type: 'credit', customer: customer)
          expect(order).to be_valid
        end

        it 'is invalid if customer does not have credit account' do
          customer = create(:customer, has_credit_account: false)
          order = build(:order, order_type: 'credit', customer: customer)
          expect(order).not_to be_valid
          expect(order.errors[:base]).to include("Credit orders require a customer with credit account enabled")
        end

        it 'allows nil customer (validation is skipped)' do
          order = build(:order, order_type: 'credit', customer: nil)
          # El error vendrá de la validación de numericality de total_amount o de belongs_to
          # pero no de credit_order_requires_credit_account
          order.valid?
          expect(order.errors[:base]).not_to include("Credit orders require a customer with credit account enabled")
        end
      end
    end

    describe 'total_amount validation' do
      it 'is invalid if total_amount is 0' do
        order = build(:order, total_amount: 0)
        expect(order).not_to be_valid
        expect(order.errors[:total_amount]).to be_present
      end

      it 'is invalid if total_amount is negative' do
        order = build(:order, total_amount: -10)
        expect(order).not_to be_valid
        expect(order.errors[:total_amount]).to be_present
      end

      it 'is valid if total_amount is positive' do
        order = build(:order, total_amount: 100)
        expect(order).to be_valid
      end
    end
  end

  describe 'scopes' do
    let!(:cash_order) { create(:order, order_type: 'cash') }
    let!(:credit_order) { create(:order, :credit_order) }
    let!(:cancelled_order) { create(:order, :cancelled) }

    describe '.cash' do
      it 'returns only cash orders' do
        expect(Order.cash).to include(cash_order)
        expect(Order.cash).not_to include(credit_order)
      end
    end

    describe '.credit' do
      it 'returns only credit orders' do
        expect(Order.credit).to include(credit_order)
        expect(Order.credit).not_to include(cash_order)
      end
    end

    describe '.active' do
      it 'returns only non-cancelled orders' do
        expect(Order.active).to include(cash_order, credit_order)
        expect(Order.active).not_to include(cancelled_order)
      end
    end
  end

  describe '#calculate_total!' do
    it 'calculates and updates total_amount from order_items' do
      order = create(:order, total_amount: 1) # Start with valid amount
      product1 = create(:product, price_unit: 10)
      product2 = create(:product, price_unit: 20)

      create(:order_item, order: order, product: product1, quantity: 2, unit_price: 10)
      create(:order_item, order: order, product: product2, quantity: 3, unit_price: 20)

      order.calculate_total!

      expect(order.reload.total_amount).to eq(80) # (2 * 10) + (3 * 20)
    end
  end

  describe 'business rules' do
    it 'allows a customer to have both cash and credit orders' do
      customer = create(:customer, has_credit_account: true)

      cash_order = create(:order, order_type: 'cash', customer: customer)
      credit_order = create(:order, order_type: 'credit', customer: customer)

      expect(cash_order).to be_valid
      expect(credit_order).to be_valid
      expect(customer.orders).to include(cash_order, credit_order)
    end

    it 'credit orders are only for customers with credit account enabled' do
      customer_without_credit = create(:customer, has_credit_account: false)
      customer_with_credit = create(:customer, has_credit_account: true)

      order1 = build(:order, order_type: 'credit', customer: customer_without_credit)
      order2 = build(:order, order_type: 'credit', customer: customer_with_credit)

      expect(order1).not_to be_valid
      expect(order2).to be_valid
    end
  end
end
