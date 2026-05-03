# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Web::Orders", type: :request do
  let!(:stock_location) { create(:stock_location) }
  let(:vendedor) { create(:user, role: "vendedor") }
  let(:customer_with_credit) { create(:customer, :with_credit) }
  let(:product) { create(:product, current_stock: 50, price_unit: 100) }

  before { sign_in vendedor }

  describe "POST /web/orders" do
    let(:base_params) do
      {
        order: {
          customer_id: customer_with_credit.id,
          order_type: "credit",
          channel: "counter"
        },
        purchase_items: [
          { product_id: product.id, quantity: "2", unit_price: "100" }
        ],
        sale_date: Date.today.iso8601,
        paper_number: "0099"
      }
    end

    context "with initial_payment_amount on a credit order" do
      it "creates Order and a Payment tied to it" do
        expect {
          post "/web/orders", params: base_params.merge(
            initial_payment_amount: "50",
            initial_payment_method: "cash"
          )
        }.to change(Order, :count).by(1).and change(Payment, :count).by(1)

        order = Order.order(:created_at).last
        payment = Payment.order(:created_at).last
        expect(payment.order_id).to eq(order.id)
        expect(payment.amount).to eq(50)
        expect(payment.payment_method).to eq("cash")
      end
    end

    context "with initial_payment_amount on an immediate order" do
      it "ignores the amount and creates only the Order" do
        retail_customer = create(:customer, has_credit_account: false)

        expect {
          post "/web/orders", params: base_params.deep_merge(
            order: { customer_id: retail_customer.id, order_type: "immediate" }
          ).merge(
            initial_payment_amount: "50",
            initial_payment_method: "cash"
          )
        }.to change(Order, :count).by(1).and change(Payment, :count).by(0)
      end
    end

    context "with no initial_payment_amount on a credit order" do
      it "creates the Order with no Payment" do
        expect {
          post "/web/orders", params: base_params
        }.to change(Order, :count).by(1).and change(Payment, :count).by(0)
      end
    end

    context "with initial_payment_amount = 0 on a credit order" do
      it "creates the Order with no Payment" do
        expect {
          post "/web/orders", params: base_params.merge(
            initial_payment_amount: "0",
            initial_payment_method: "cash"
          )
        }.to change(Order, :count).by(1).and change(Payment, :count).by(0)
      end
    end
  end
end
