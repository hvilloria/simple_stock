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

    # Big order to exercise realistic discounts (≥ 100) without the ceil
    # overshooting above the original total.
    let(:big_order) do
      o = create(:order, :on_account, customer: customer,
                 total_amount: 710_775, original_total_amount: 710_775)
      create(:order_item, order: o, product: product, quantity: 1, unit_price: 710_775)
      o
    end

    # Canonical: 710.775 × 0,90 = 639.697,5 → nearest-100 = 639.700.
    it "rounds the discounted cash to the nearest hundred and settles the account" do
      result = described_class.call(
        order: big_order, amount_to_settle: 710_775,
        discount_percent: 10, tenders: [ { payment_method: "cash", amount: 639_700 } ]
      )

      expect(result).to be_success
      expect(big_order.reload.total_amount).to eq(639_700)
      expect(big_order.original_total_amount).to eq(710_775)
      expect(big_order.payment_allocations.sum(:amount)).to eq(639_700)
      expect(big_order.outstanding_balance).to eq(0)
      expect(big_order.status).to eq("confirmed")
    end

    # cash_raw already a multiple of 100: 300.000 × 0,90 = 270.000 → stays 270.000.
    it "applies a partial cash discount when the cash is already a multiple of 100" do
      result = described_class.call(
        order: big_order, amount_to_settle: 300_000,
        discount_percent: 10, tenders: [ { payment_method: "cash", amount: 270_000 } ]
      )

      expect(result).to be_success
      expect(big_order.reload.total_amount).to eq(680_775)         # 710.775 − 30.000 effective discount
      expect(big_order.payment_allocations.sum(:amount)).to eq(270_000)
      expect(big_order.outstanding_balance).to eq(410_775)
    end

    # cash_raw NOT a multiple: 250.001 × 0,90 = 225.000,9 → nearest-100 = 225.000.
    it "rounds a non-multiple partial cash to the nearest hundred" do
      result = described_class.call(
        order: big_order, amount_to_settle: 250_001,
        discount_percent: 10, tenders: [ { payment_method: "cash", amount: 225_000 } ]
      )

      expect(result).to be_success
      expect(big_order.reload.total_amount).to eq(685_774)         # 710.775 − 25.001 effective discount
      expect(big_order.payment_allocations.sum(:amount)).to eq(225_000)
      expect(big_order.outstanding_balance).to eq(460_774)
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
