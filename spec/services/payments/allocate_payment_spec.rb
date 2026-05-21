# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::AllocatePayment, type: :service do
  let!(:stock_location) { create(:stock_location) }
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
      order_type: "credit"
    ).record
  end

  let(:order_b) do
    Sales::CreateOrder.call(
      customer: customer,
      items: [ { product_id: product.id, quantity: 2, unit_price: 100 } ],
      order_type: "credit"
    ).record
  end

  describe ".call" do
    context "with invalid input" do
      it "fails when customer has no credit account" do
        retail = create(:customer, has_credit_account: false)
        result = described_class.call(
          customer: retail,
          payment_date: Date.today,
          allocations: [ { order_id: order_a.id, amount: 100, payment_method: "cash" } ]
        )
        expect(result.failure?).to be true
        expect(result.errors.join).to match(/cuenta corriente/i)
      end

      it "fails when allocations is empty" do
        result = described_class.call(
          customer: customer,
          payment_date: Date.today,
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
          order_type: "credit"
        ).record

        result = described_class.call(
          customer: customer,
          payment_date: Date.today,
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
          payments: [ { amount: 100, payment_method: "cash" } ]
        ).record

        result = described_class.call(
          customer: customer,
          payment_date: Date.today,
          allocations: [ { order_id: immediate.id, amount: 50, payment_method: "cash" } ]
        )
        expect(result.failure?).to be true
      end

      it "fails when amount exceeds outstanding balance of an order" do
        result = described_class.call(
          customer: customer,
          payment_date: Date.today,
          allocations: [ { order_id: order_a.id, amount: order_a.total_amount + 1, payment_method: "cash" } ]
        )
        expect(result.failure?).to be true
        expect(result.errors.join).to match(/saldo pendiente/i)
      end

      it "fails when payment_method is invalid" do
        result = described_class.call(
          customer: customer,
          payment_date: Date.today,
          allocations: [ { order_id: order_a.id, amount: 50, payment_method: "bitcoin" } ]
        )
        expect(result.failure?).to be true
        expect(result.errors.join).to match(/método de pago/i)
      end
    end

    context "with valid input — single method" do
      it "creates one Payment grouping all allocations under that method" do
        expect {
          described_class.call(
            customer: customer,
            payment_date: Date.today,
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
          payment_date: Date.today,
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
            payment_date: Date.today,
            allocations: [
              { order_id: order_a.id, amount: 100, payment_method: "cash" },
              { order_id: order_b.id, amount: 80, payment_method: "transfer" }
            ]
          )
        }.to change(Payment, :count).by(2)
         .and change(PaymentAllocation, :count).by(2)

        cash_payment = Payment.find_by(payment_method: "cash")
        transfer_payment = Payment.find_by(payment_method: "transfer")
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
            payment_date: Date.today,
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
          payment_date: Date.today,
          notes: "Pago semanal",
          allocations: [
            { order_id: order_a.id, amount: 100, payment_method: "cash" },
            { order_id: order_b.id, amount: 80, payment_method: "transfer" }
          ]
        )
        expect(Payment.pluck(:notes).uniq).to eq([ "Pago semanal" ])
      end
    end
  end
end
