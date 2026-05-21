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

    context "credit order with no payments" do
      it "creates Order and no Payment" do
        expect {
          post "/web/orders", params: base_params
        }.to change(Order, :count).by(1).and change(Payment, :count).by(0)
      end
    end

    context "credit order with a partial payment" do
      it "creates Order + 1 Payment + 1 Allocation" do
        params = base_params.merge(
          payments: { "0" => { amount: "50", payment_method: "cash" } }
        )
        expect {
          post "/web/orders", params: params
        }.to change(Order, :count).by(1)
          .and change(Payment, :count).by(1)
          .and change(PaymentAllocation, :count).by(1)

        order   = Order.order(:created_at).last
        payment = Payment.order(:created_at).last
        expect(payment.amount).to eq(50)
        expect(payment.payment_method).to eq("cash")
        expect(order.payment_allocations.first.payment_id).to eq(payment.id)
      end
    end

    context "immediate order with matching single payment" do
      it "creates Order + Payment + Allocation" do
        retail = create(:customer, has_credit_account: false, name: "Walk-in")
        params = base_params.deep_merge(
          order: { customer_id: retail.id, order_type: "immediate" }
        ).merge(
          payments: { "0" => { amount: "200", payment_method: "cash" } }
        )

        expect {
          post "/web/orders", params: params
        }.to change(Order, :count).by(1)
          .and change(Payment, :count).by(1)
          .and change(PaymentAllocation, :count).by(1)
      end
    end

    context "immediate order with split payments" do
      it "creates one Payment per row" do
        retail = create(:customer, has_credit_account: false, name: "Walk-in")
        params = base_params.deep_merge(
          order: { customer_id: retail.id, order_type: "immediate" }
        ).merge(
          payments: {
            "0" => { amount: "120", payment_method: "cash" },
            "1" => { amount: "80",  payment_method: "transfer" }
          }
        )

        expect {
          post "/web/orders", params: params
        }.to change(Order, :count).by(1)
          .and change(Payment, :count).by(2)
          .and change(PaymentAllocation, :count).by(2)
      end
    end

    context "immediate order without payments" do
      it "fails and renders new" do
        retail = create(:customer, has_credit_account: false, name: "Walk-in")
        params = base_params.deep_merge(
          order: { customer_id: retail.id, order_type: "immediate" }
        )

        expect {
          post "/web/orders", params: params
        }.to change(Order, :count).by(0)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "POST /web/orders with discount_percent" do
    let(:retail_customer) { create(:customer, has_credit_account: false, name: "Walk-in") }

    def discount_params(discount:, payment_amount:)
      {
        order: {
          order_type: "immediate",
          customer_id: retail_customer.id,
          channel: "counter"
        },
        purchase_items: [
          { product_id: product.id.to_s, quantity: "1", unit_price: "1000" }
        ],
        payments: { "0" => { amount: payment_amount.to_s, payment_method: "cash" } },
        source: "live",
        sale_date: Date.today.iso8601,
        paper_number: "0099",
        discount_percent: discount.to_s
      }
    end

    context "valid 10% discount" do
      it "creates the order with post-discount total and stores original_total_amount" do
        post "/web/orders", params: discount_params(discount: 10, payment_amount: 900)
        expect(response).to redirect_to(web_orders_path)

        order = Order.order(:created_at).last
        expect(order.total_amount.to_f).to eq(900.0)
        expect(order.original_total_amount.to_f).to eq(1000.0)
        expect(order.order_items.first.discount_percent.to_i).to eq(10)
      end
    end

    context "discount above immediate cap" do
      it "re-renders new with the 10% error" do
        post "/web/orders", params: discount_params(discount: 15, payment_amount: 850)
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to match(/10%/)
      end
    end
  end
end
