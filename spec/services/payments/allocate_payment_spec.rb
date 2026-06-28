# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::AllocatePayment, type: :service do
  let!(:stock_location) { create(:stock_location) }
  let(:user) { create(:user) }
  let(:customer) { create(:customer, :with_credit) }
  let(:product) do
    p = create(:product, current_stock: 0, price_unit: 100)
    create(:stock_movement, product: p, stock_location: stock_location, quantity: 50, movement_type: "purchase")
    p.recalculate_current_stock!
    p
  end

  let(:order_a) do
    Sales::CreateOrder.call(
      customer: customer,
      items: [ { product_id: product.id, quantity: 3, unit_price: 100 } ],
      order_type: "credit",
      paper_number: "AP-001",
      user: user
    ).record
  end

  let(:order_b) do
    Sales::CreateOrder.call(
      customer: customer,
      items: [ { product_id: product.id, quantity: 2, unit_price: 100 } ],
      order_type: "credit",
      paper_number: "AP-002",
      user: user
    ).record
  end

  describe ".call" do
    context "with invalid input" do
      it "fails when customer has no credit account" do
        retail = create(:customer, has_credit_account: false)
        result = described_class.call(
          customer: retail,
          payment_date: Date.current,
          allocations: [ { order_id: order_a.id, amount: 100, payment_method: "cash" } ]
        )
        expect(result.failure?).to be true
        expect(result.errors.join).to match(/cuenta corriente/i)
      end

      it "fails when allocations is empty" do
        result = described_class.call(
          customer: customer,
          payment_date: Date.current,
          allocations: []
        )
        expect(result.failure?).to be true
        expect(result.errors.join).to match(/al menos una orden/i)
      end

      it "fails when an order does not belong to the customer" do
        other_customer = create(:customer, :with_credit)
        foreign_order = Sales::CreateOrder.call(
          customer: other_customer,
          items: [ { product_id: product.id, quantity: 1, unit_price: 100 } ],
          order_type: "credit",
          paper_number: "AP-003",
          user: user
        ).record

        result = described_class.call(
          customer: customer,
          payment_date: Date.current,
          allocations: [ { order_id: foreign_order.id, amount: 50, payment_method: "cash" } ]
        )
        expect(result.failure?).to be true
        expect(result.errors.join).to match(/no pertenece/i)
      end

      it "fails when an order is not credit" do
        immediate = Sales::CreateOrder.call(
          customer: Customer.mostrador,
          items: [ { product_id: product.id, quantity: 1, unit_price: 100 } ],
          order_type: "immediate",
          paper_number: "AP-004",
          user: user
        ).record

        result = described_class.call(
          customer: customer,
          payment_date: Date.current,
          allocations: [ { order_id: immediate.id, amount: 50, payment_method: "cash" } ]
        )
        expect(result.failure?).to be true
      end

      it "fails when amount exceeds outstanding balance of an order" do
        result = described_class.call(
          customer: customer,
          payment_date: Date.current,
          allocations: [ { order_id: order_a.id, amount: order_a.total_amount + 1, payment_method: "cash" } ]
        )
        expect(result.failure?).to be true
        expect(result.errors.join).to match(/saldo pendiente/i)
      end

      it "fails when payment_method is invalid" do
        result = described_class.call(
          customer: customer,
          payment_date: Date.current,
          allocations: [ { order_id: order_a.id, amount: 50, payment_method: "bitcoin" } ]
        )
        expect(result.failure?).to be true
        expect(result.errors.join).to match(/método de pago/i)
      end

      it "rejects an Argentine-formatted amount string instead of silently truncating it (backstop)" do
        result = described_class.call(
          customer: customer,
          payment_date: Date.current,
          allocations: [ { order_id: order_a.id, amount: "80.000,00", payment_method: "cash" } ]
        )
        expect(result.failure?).to be true
        expect(result.errors.join).to match(/formato inválido/i)
        expect(Payment.count).to eq(0)
      end
    end

    context "with valid input — single method" do
      it "creates one Payment grouping all allocations under that method" do
        expect {
          described_class.call(
            customer: customer,
            payment_date: Date.current,
            allocations: [
              { order_id: order_a.id, amount: 100, payment_method: "cash" },
              { order_id: order_b.id, amount: 80, payment_method: "cash" }
            ]
          )
        }.to change(Payment, :count).by(1)
         .and change(PaymentAllocation, :count).by(2)

        payment = Payment.last
        expect(payment.amount).to eq(180)
        expect(payment.payment_method).to eq("cash")
        expect(payment.allocations.pluck(:amount).sort).to eq([ 80, 100 ])
      end

      it "returns Result.success with the array of created Payments in record" do
        result = described_class.call(
          customer: customer,
          payment_date: Date.current,
          allocations: [ { order_id: order_a.id, amount: 100, payment_method: "cash" } ]
        )
        expect(result.success?).to be true
        expect(result.record).to be_an(Array)
        expect(result.record.size).to eq(1)
        expect(result.record.first).to be_a(Payment)
      end
    end

    context "with valid input — mixed methods" do
      it "creates one Payment per payment_method group" do
        expect {
          described_class.call(
            customer: customer,
            payment_date: Date.current,
            allocations: [
              { order_id: order_a.id, amount: 100, payment_method: "cash" },
              { order_id: order_b.id, amount: 80, payment_method: "bank_transfer" }
            ]
          )
        }.to change(Payment, :count).by(2)
         .and change(PaymentAllocation, :count).by(2)

        cash_payment = Payment.find_by(payment_method: "cash")
        transfer_payment = Payment.find_by(payment_method: "bank_transfer")
        expect(cash_payment.amount).to eq(100)
        expect(transfer_payment.amount).to eq(80)
      end
    end

    context "transaction safety" do
      it "rolls back everything when a later allocation fails" do
        bad_amount = order_b.total_amount + 1
        expect {
          described_class.call(
            customer: customer,
            payment_date: Date.current,
            allocations: [
              { order_id: order_a.id, amount: 100, payment_method: "cash" },
              { order_id: order_b.id, amount: bad_amount, payment_method: "cash" }
            ]
          )
        }.to change(Payment, :count).by(0)
         .and change(PaymentAllocation, :count).by(0)
      end
    end

    context "notes" do
      it "saves the notes on every created Payment" do
        described_class.call(
          customer: customer,
          payment_date: Date.current,
          notes: "Pago semanal",
          allocations: [
            { order_id: order_a.id, amount: 100, payment_method: "cash" },
            { order_id: order_b.id, amount: 80, payment_method: "bank_transfer" }
          ]
        )
        expect(Payment.pluck(:notes).uniq).to eq([ "Pago semanal" ])
      end
    end

    context "with item_discounts on the first cobro of an order" do
      let(:multi_item_order) do
        Sales::CreateOrder.call(
          customer: customer,
          items: [
            { product_id: product.id, quantity: 2, unit_price: 100 },
            { product_id: product.id, quantity: 1, unit_price: 100 }
          ],
          order_type: "credit",
          paper_number: "AP-005",
          user: user
        ).record
      end

      it "applies the per-item discounts, recalculates total_amount, and creates the allocation" do
        items = multi_item_order.order_items.order(:id).to_a
        result = described_class.call(
          customer: customer,
          payment_date: Date.current,
          allocations: [
            {
              order_id: multi_item_order.id,
              amount: 260,
              payment_method: "cash",
              item_discounts: { items.first.id => 10, items.last.id => 20 }
            }
          ]
        )

        expect(result.success?).to be true
        multi_item_order.reload
        expect(multi_item_order.original_total_amount.to_f).to eq(300.0)
        expect(multi_item_order.total_amount.to_f).to eq(260.0)
        items.each(&:reload)
        expect(items.first.discount_percent.to_i).to eq(10)
        expect(items.last.discount_percent.to_i).to eq(20)
        expect(multi_item_order.payment_allocations.sum(:amount).to_f).to eq(260.0)
      end

      it "ignores item_discounts when the order already has an allocation (locked)" do
        items = multi_item_order.order_items.order(:id).to_a

        described_class.call(
          customer: customer,
          payment_date: Date.current,
          allocations: [
            {
              order_id: multi_item_order.id,
              amount: 50,
              payment_method: "cash",
              item_discounts: { items.first.id => 10, items.last.id => 0 }
            }
          ]
        )

        multi_item_order.reload
        locked_total = multi_item_order.total_amount.to_f

        result = described_class.call(
          customer: customer,
          payment_date: Date.current,
          allocations: [
            {
              order_id: multi_item_order.id,
              amount: 30,
              payment_method: "cash",
              item_discounts: { items.first.id => 20, items.last.id => 20 }
            }
          ]
        )

        expect(result.success?).to be true
        multi_item_order.reload
        items.each(&:reload)
        expect(multi_item_order.total_amount.to_f).to eq(locked_total)
        expect(items.first.discount_percent.to_i).to eq(10)
        expect(items.last.discount_percent.to_i).to eq(0)
      end

      it "fails when a percent is outside 0..20" do
        items = multi_item_order.order_items.order(:id).to_a
        result = described_class.call(
          customer: customer,
          payment_date: Date.current,
          allocations: [
            {
              order_id: multi_item_order.id,
              amount: 100,
              payment_method: "cash",
              item_discounts: { items.first.id => 25 }
            }
          ]
        )
        expect(result.failure?).to be true
        expect(result.errors.join).to match(/0-20/)
      end

      it "ignores item_discounts entries referencing items that do not belong to the order" do
        items = multi_item_order.order_items.order(:id).to_a
        other_order = Sales::CreateOrder.call(
          customer: customer,
          items: [ { product_id: product.id, quantity: 1, unit_price: 100 } ],
          order_type: "credit",
          paper_number: "AP-006",
          user: user
        ).record
        foreign_item_id = other_order.order_items.first.id

        result = described_class.call(
          customer: customer,
          payment_date: Date.current,
          allocations: [
            {
              order_id: multi_item_order.id,
              amount: 270, # 10% on first item => total 280; 270 fits within outstanding balance
              payment_method: "cash",
              item_discounts: { items.first.id => 10, foreign_item_id => 20 }
            }
          ]
        )

        expect(result.success?).to be true
        multi_item_order.reload
        items.each(&:reload)
        expect(items.first.discount_percent.to_i).to eq(10)
        expect(items.last.discount_percent.to_i).to eq(0)
      end
    end

    describe "status promotion" do
      let(:customer) { create(:customer, :with_credit) }
      let(:order) do
        create(:order, :pending, :credit_order,
               customer: customer,
               total_amount: 1000,
               original_total_amount: 1000)
      end

      it "accepts a pending credit order (no longer requires confirmed)" do
        result = described_class.call(
          customer: customer,
          payment_date: Date.current,
          allocations: [ { order_id: order.id, amount: 400, payment_method: "cash" } ]
        )

        expect(result).to be_success
        expect(order.reload.status).to eq("pending")
      end

      it "promotes the order to confirmed when balance reaches 0" do
        described_class.call(
          customer: customer,
          payment_date: Date.current,
          allocations: [ { order_id: order.id, amount: 1000, payment_method: "cash" } ]
        )

        expect(order.reload.status).to eq("confirmed")
      end

      it "keeps pending after a partial then promotes on the final allocation" do
        described_class.call(
          customer: customer,
          payment_date: Date.current,
          allocations: [ { order_id: order.id, amount: 600, payment_method: "cash" } ]
        )
        expect(order.reload.status).to eq("pending")

        described_class.call(
          customer: customer,
          payment_date: Date.current,
          allocations: [ { order_id: order.id, amount: 400, payment_method: "cash" } ]
        )
        expect(order.reload.status).to eq("confirmed")
      end
    end
  end
end
