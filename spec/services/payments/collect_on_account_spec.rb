require "rails_helper"

RSpec.describe Payments::CollectOnAccount do
  let(:customer) { Customer.mostrador }
  let(:product) { create(:product, price_unit: 100) }
  let(:order) do
    o = create(:order, :on_account,
               customer: customer, total_amount: 1000, original_total_amount: 1000)
    create(:order_item, order: o, product: product, quantity: 10, unit_price: 100)
    o
  end

  describe ".call" do
    it "collects a partial cash payment and lowers the balance, staying pending" do
      result = described_class.call(
        order: order, amount_to_settle: 400,
        discount_percent: 0, tenders: [ { payment_method: "cash", amount: 400 } ]
      )

      expect(result).to be_success
      expect(order.reload.outstanding_balance).to eq(600)
      expect(order.status).to eq("pending")
      expect(order.payment_allocations.sum(:amount)).to eq(400)
    end

    it "applies a per-event cash discount, lowering total_amount and balance" do
      result = described_class.call(
        order: order, amount_to_settle: 500,
        discount_percent: 10, tenders: [ { payment_method: "cash", amount: 450 } ]
      )

      expect(result).to be_success
      expect(order.reload.total_amount).to eq(950)
      expect(order.original_total_amount).to eq(1000)
      expect(order.payment_allocations.sum(:amount)).to eq(450)
      expect(order.outstanding_balance).to eq(500)
    end

    it "rejects amount_to_settle greater than the outstanding balance" do
      result = described_class.call(
        order: order, amount_to_settle: 1500,
        discount_percent: 0, tenders: [ { payment_method: "cash", amount: 1500 } ]
      )
      expect(result).to be_failure
    end

    it "rejects a discount when any tender is not cash" do
      result = described_class.call(
        order: order, amount_to_settle: 500,
        discount_percent: 10, tenders: [ { payment_method: "bank_transfer", amount: 450 } ]
      )
      expect(result).to be_failure
    end

    it "rejects when tenders do not sum to the cash to collect" do
      result = described_class.call(
        order: order, amount_to_settle: 400,
        discount_percent: 0, tenders: [ { payment_method: "cash", amount: 300 } ]
      )
      expect(result).to be_failure
    end

    it "promotes the order to confirmed when the final payment settles it" do
      described_class.call(order: order, amount_to_settle: 600,
                           discount_percent: 0, tenders: [ { payment_method: "cash", amount: 600 } ])
      result = described_class.call(order: order.reload, amount_to_settle: 400,
                                    discount_percent: 0, tenders: [ { payment_method: "cash", amount: 400 } ])

      expect(result).to be_success
      expect(order.reload.outstanding_balance).to eq(0)
      expect(order.status).to eq("confirmed")
    end

    it "rejects a non on_account order" do
      immediate = create(:order, :pending, order_type: "immediate",
                         total_amount: 100, original_total_amount: 100)
      result = described_class.call(order: immediate, amount_to_settle: 100,
                                    discount_percent: 0, tenders: [ { payment_method: "cash", amount: 100 } ])
      expect(result).to be_failure
    end
  end
end
