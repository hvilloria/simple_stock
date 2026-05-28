require 'rails_helper'

RSpec.describe Order, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:customer).optional }
    it { is_expected.to have_many(:order_items).dependent(:destroy) }
  end

  describe 'enums' do
    it { is_expected.to define_enum_for(:status).with_values(pending: 'pending', confirmed: 'confirmed', cancelled: 'cancelled').backed_by_column_of_type(:string).with_suffix }
    it { is_expected.to define_enum_for(:order_type).with_values(immediate: 'immediate', credit: 'credit').backed_by_column_of_type(:string).with_suffix }
  end

  describe 'status enum' do
    it 'includes pending' do
      expect(Order.statuses.keys).to include('pending')
    end

    it 'exposes pending_status? predicate' do
      expect(build(:order, status: 'pending').pending_status?).to be true
    end
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
      context 'when order_type is immediate' do
        it 'is valid even if customer does not have credit account' do
          customer = create(:customer, has_credit_account: false)
          order = build(:order, order_type: 'immediate', customer: customer)
          expect(order).to be_valid
        end
      end

      context 'when order_type is credit' do
        it 'is valid if customer has credit account' do
          customer = create(:customer, customer_type: "workshop", has_credit_account: true)
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

    describe 'source validation' do
      it 'allows live source' do
        order = build(:order, source: 'live')
        expect(order).to be_valid
      end

      it 'allows from_paper source' do
        order = build(:order, source: 'from_paper', total_amount: 0, paper_number: '0001')
        expect(order).to be_valid
      end

      it 'rejects invalid source' do
        order = build(:order, source: 'invalid')
        expect(order).not_to be_valid
      end
    end

    describe 'paper_number validation' do
      it 'requires paper_number for from_paper orders' do
        order = build(:order, source: 'from_paper', total_amount: 0, paper_number: nil)
        expect(order).not_to be_valid
        expect(order.errors[:paper_number]).to be_present
      end

      it 'is valid for from_paper orders with paper_number' do
        order = build(:order, source: 'from_paper', total_amount: 0, paper_number: '0042')
        expect(order).to be_valid
      end

      it 'is required for live orders' do
        order = build(:order, source: 'live', paper_number: nil)
        expect(order).not_to be_valid
        expect(order.errors[:paper_number]).to include("can't be blank")
      end
    end

    describe 'total_amount validation with from_paper source' do
      it 'allows total_amount = 0 for from_paper orders' do
        order = build(:order, source: 'from_paper', total_amount: 0, paper_number: '0001')
        expect(order).to be_valid
      end

      it 'requires total_amount > 0 for live orders' do
        order = build(:order, source: 'live', total_amount: 0)
        expect(order).not_to be_valid
        expect(order.errors[:total_amount]).to be_present
      end
    end

    describe 'sale_date validation' do
      it 'requires sale_date' do
        order = build(:order, sale_date: nil)
        expect(order).not_to be_valid
      end

      it 'allows past sale_date' do
        order = build(:order, sale_date: 1.week.ago.to_date)
        expect(order).to be_valid
      end
    end
  end

  describe 'scopes' do
    let!(:immediate_order) { create(:order, order_type: 'immediate') }
    let!(:credit_order) { create(:order, :credit_order) }
    let!(:cancelled_order) { create(:order, :cancelled) }
    let!(:live_order) { create(:order, source: 'live') }
    let!(:paper_order) { create(:order, :from_paper) }

    describe '.immediate' do
      it 'returns only immediate orders' do
        expect(Order.immediate).to include(immediate_order)
        expect(Order.immediate).not_to include(credit_order)
      end
    end

    describe '.credit' do
      it 'returns only credit orders' do
        expect(Order.credit).to include(credit_order)
        expect(Order.credit).not_to include(immediate_order)
      end
    end

    describe '.active' do
      it 'returns only non-cancelled orders' do
        expect(Order.active).to include(immediate_order, credit_order)
        expect(Order.active).not_to include(cancelled_order)
      end
    end

    describe '.live' do
      it 'returns only live orders' do
        expect(Order.live).to include(live_order)
        expect(Order.live).not_to include(paper_order)
      end
    end

    describe '.from_paper' do
      it 'returns only from_paper orders' do
        expect(Order.from_paper).to include(paper_order)
        expect(Order.from_paper).not_to include(live_order)
      end
    end
  end

  describe '#calculate_total!' do
    it 'calculates and updates total_amount from order_items' do
      order = create(:order, total_amount: 1, original_total_amount: 80) # Start with valid amount; original matches future calculated total
      product1 = create(:product, price_unit: 10)
      product2 = create(:product, price_unit: 20)

      create(:order_item, order: order, product: product1, quantity: 2, unit_price: 10)
      create(:order_item, order: order, product: product2, quantity: 3, unit_price: 20)

      order.calculate_total!

      expect(order.reload.total_amount).to eq(80) # (2 * 10) + (3 * 20)
    end
  end

  describe '#from_paper?' do
    it 'returns true for from_paper orders' do
      order = build(:order, source: 'from_paper')
      expect(order.from_paper?).to be true
    end

    it 'returns false for live orders' do
      order = build(:order, source: 'live')
      expect(order.from_paper?).to be false
    end
  end

  describe "#outstanding_balance (factory-based)" do
    it "is total_amount minus allocations for any non-cancelled order" do
      order = create(:order, :pending, total_amount: 1000, original_total_amount: 1000)
      expect(order.outstanding_balance).to eq(1000)
    end

    it "is zero for cancelled orders" do
      order = create(:order, :pending, total_amount: 1000, original_total_amount: 1000)
      order.update_column(:status, "cancelled")
      expect(order.outstanding_balance).to eq(0)
    end
  end

  describe "#refresh_status_from_balance!" do
    it "promotes pending to confirmed when balance reaches 0" do
      order = create(:order, :pending, total_amount: 1000, original_total_amount: 1000)
      allow(order).to receive(:outstanding_balance).and_return(0)
      order.refresh_status_from_balance!
      expect(order.reload.status).to eq("confirmed")
    end

    it "keeps pending when balance > 0" do
      order = create(:order, :pending, total_amount: 1000, original_total_amount: 1000)
      allow(order).to receive(:outstanding_balance).and_return(500)
      order.refresh_status_from_balance!
      expect(order.reload.status).to eq("pending")
    end

    it "is a no-op for cancelled orders" do
      order = create(:order, :pending, total_amount: 1000, original_total_amount: 1000)
      order.update_column(:status, "cancelled")
      order.refresh_status_from_balance!
      expect(order.reload.status).to eq("cancelled")
    end
  end

  describe "#outstanding_balance with allocations" do
    let(:customer) { create(:customer, :with_credit) }
    let(:order) { create(:order, :pending, :credit_order, customer: customer, total_amount: 200, original_total_amount: 200) }

    it "returns total minus allocated amount on partial payment" do
      payment = create(:payment, customer: customer, amount: 50)
      create(:payment_allocation, payment: payment, order: order, amount: 50)
      expect(order.outstanding_balance).to eq(150)
    end

    it "returns 0 when fully allocated" do
      payment = create(:payment, customer: customer, amount: 200)
      create(:payment_allocation, payment: payment, order: order, amount: 200)
      expect(order.outstanding_balance).to eq(0)
    end
  end

  describe "original_total_amount" do
    let(:customer) { Customer.create!(name: "T", customer_type: "retail") }

    it "is invalid without original_total_amount" do
      order = Order.new(customer: customer, order_type: "immediate", source: "live",
                        sale_date: Date.today, total_amount: 100, status: "confirmed")
      expect(order).not_to be_valid
      expect(order.errors[:original_total_amount]).to be_present
    end

    it "is invalid when original_total_amount < total_amount" do
      order = Order.new(customer: customer, order_type: "immediate", source: "live", paper_number: "9001",
                        sale_date: Date.today, total_amount: 100, original_total_amount: 50, status: "confirmed")
      expect(order).not_to be_valid
      expect(order.errors[:original_total_amount]).to be_present
    end

    it "is valid when original_total_amount == total_amount" do
      order = Order.new(customer: customer, order_type: "immediate", source: "live", paper_number: "9002",
                        sale_date: Date.today, total_amount: 100, original_total_amount: 100, status: "confirmed")
      expect(order).to be_valid
    end
  end

  describe "#discount_amount" do
    let(:customer) { Customer.create!(name: "T", customer_type: "retail") }

    it "returns original_total_amount - total_amount" do
      order = Order.create!(customer: customer, order_type: "immediate", source: "live", paper_number: "9003",
                            sale_date: Date.today, total_amount: 90, original_total_amount: 100, status: "confirmed")
      expect(order.discount_amount).to eq(10)
    end

    it "returns 0 when no discount was applied" do
      order = Order.create!(customer: customer, order_type: "immediate", source: "live", paper_number: "9004",
                            sale_date: Date.today, total_amount: 100, original_total_amount: 100, status: "confirmed")
      expect(order.discount_amount).to eq(0)
    end
  end

  describe "#discount_percent_display" do
    let(:customer) { Customer.create!(name: "T", customer_type: "retail") }
    let(:product) { Product.create!(sku: "X", name: "P", price_unit: 100, cost_unit: 50, cost_currency: "ARS") }

    it "returns the first item's discount_percent as an integer" do
      order = Order.create!(customer: customer, order_type: "immediate", source: "live", paper_number: "9005",
                            sale_date: Date.today, total_amount: 90, original_total_amount: 100, status: "confirmed")
      order.order_items.create!(product: product, quantity: 1, unit_price: 100, discount_percent: 10)
      expect(order.discount_percent_display).to eq(10)
    end

    it "returns 0 when there are no items" do
      order = Order.create!(customer: customer, order_type: "immediate", source: "live", paper_number: "9006",
                            sale_date: Date.today, total_amount: 100, original_total_amount: 100, status: "confirmed")
      expect(order.discount_percent_display).to eq(0)
    end
  end

  describe 'business rules' do
    it 'allows a customer to have both immediate and credit orders' do
      customer = create(:customer, customer_type: "workshop", has_credit_account: true)

      immediate_order = create(:order, order_type: 'immediate', customer: customer)
      credit_order = create(:order, order_type: 'credit', customer: customer)

      expect(immediate_order).to be_valid
      expect(credit_order).to be_valid
      expect(customer.orders).to include(immediate_order, credit_order)
    end

    it 'credit orders are only for customers with credit account enabled' do
      customer_without_credit = create(:customer, has_credit_account: false)
      customer_with_credit = create(:customer, customer_type: "workshop", has_credit_account: true)

      order1 = build(:order, order_type: 'credit', customer: customer_without_credit)
      order2 = build(:order, order_type: 'credit', customer: customer_with_credit)

      expect(order1).not_to be_valid
      expect(order2).to be_valid
    end
  end
end
