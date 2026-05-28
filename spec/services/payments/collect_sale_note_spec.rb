require "rails_helper"

RSpec.describe Payments::CollectSaleNote do
  let(:customer) { Customer.mostrador }
  let!(:stock_location) { create(:stock_location) }
  let(:product) do
    p = create(:product, current_stock: 0, price_unit: 100)
    create(:stock_movement, product: p, stock_location: stock_location, quantity: 50, movement_type: "purchase")
    p.recalculate_current_stock!
    p
  end
  let(:order) do
    o = create(:order, :pending,
               customer: customer, order_type: "immediate",
               paper_number: "CSN-001",
               total_amount: 1000, original_total_amount: 1000)
    create(:order_item, order: o, product: product, quantity: 10, unit_price: 100, discount_percent: 0)
    o
  end

  describe ".call" do
    it "creates payment + allocation and promotes order to confirmed when paid exactly" do
      result = described_class.call(
        order: order,
        discount_percent: 0,
        tenders: [ { payment_method: "cash", amount: 1000 } ]
      )

      expect(result).to be_success
      expect(order.reload.status).to eq("confirmed")
      expect(order.payment_allocations.count).to eq(1)
      expect(order.payment_allocations.first.amount).to eq(1000)
      expect(order.payment_allocations.first.payment.payment_method).to eq("cash")
    end

    it "applies global discount and recalculates total when 100% cash and exact" do
      result = described_class.call(
        order: order,
        discount_percent: 5,
        tenders: [ { payment_method: "cash", amount: 950 } ]
      )

      expect(result).to be_success
      expect(order.reload.total_amount).to eq(950)
      expect(order.original_total_amount).to eq(1000)
      order.order_items.each { |oi| expect(oi.discount_percent).to eq(5) }
    end

    it "rejects discount when any tender is non-cash" do
      result = described_class.call(
        order: order,
        discount_percent: 5,
        tenders: [
          { payment_method: "cash", amount: 500 },
          { payment_method: "transfer", amount: 450 }
        ]
      )

      expect(result).to be_failure
      expect(result.errors.join).to match(/efectivo/i)
      expect(order.reload.status).to eq("pending")
    end

    it "rejects discount when cash tender total != new total" do
      result = described_class.call(
        order: order,
        discount_percent: 5,
        tenders: [ { payment_method: "cash", amount: 800 } ]
      )

      expect(result).to be_failure
    end

    it "rejects when tender sum != effective total (no discount)" do
      result = described_class.call(
        order: order,
        discount_percent: 0,
        tenders: [ { payment_method: "cash", amount: 999 } ]
      )

      expect(result).to be_failure
    end

    it "rejects credit orders" do
      credit_customer = create(:customer, :with_credit)
      credit = create(:order, :credit_order, :pending,
                      customer: credit_customer,
                      paper_number: "CSN-002",
                      total_amount: 100, original_total_amount: 100)
      result = described_class.call(
        order: credit,
        discount_percent: 0,
        tenders: [ { payment_method: "cash", amount: 100 } ]
      )

      expect(result).to be_failure
    end

    it "rejects already-confirmed orders" do
      order.update_column(:status, "confirmed")
      result = described_class.call(
        order: order,
        discount_percent: 0,
        tenders: [ { payment_method: "cash", amount: 1000 } ]
      )

      expect(result).to be_failure
    end

    it "rejects invalid discount values (e.g., 7)" do
      result = described_class.call(
        order: order,
        discount_percent: 7,
        tenders: [ { payment_method: "cash", amount: 930 } ]
      )

      expect(result).to be_failure
    end

    it "groups multi-tender mix into one Payment per method (no discount)" do
      result = described_class.call(
        order: order,
        discount_percent: 0,
        tenders: [
          { payment_method: "cash", amount: 600 },
          { payment_method: "transfer", amount: 400 }
        ]
      )

      expect(result).to be_success
      payments = order.payment_allocations.map(&:payment).uniq
      expect(payments.size).to eq(2)
      expect(payments.map(&:payment_method)).to contain_exactly("cash", "transfer")
    end
  end
end
