# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Web::Customers::Payments", type: :request do
  let!(:stock_location) { create(:stock_location) }
  let(:admin) { create(:user, role: "admin") }
  let(:customer) { create(:customer, :with_credit) }
  let(:product) do
    p = create(:product, current_stock: 0, price_unit: 100)
    create(:stock_movement, product: p, stock_location: stock_location, quantity: 50, movement_type: "purchase")
    p.recalculate_current_stock!
    p
  end

  before { sign_in admin }

  describe "GET /web/customers/:id/payments/new" do
    context "when customer has pending credit orders" do
      before do
        Sales::CreateOrder.call(
          customer: customer,
          items: [ { product_id: product.id, quantity: 2, unit_price: 100 } ],
          order_type: "credit"
        )
      end

      it "returns 200 and renders the form" do
        get new_web_customer_payment_path(customer)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Registrar Cobro")
        expect(response.body).to include("Órdenes pendientes")
      end
    end

    context "when customer has no credit account" do
      let(:no_credit_customer) { create(:customer, has_credit_account: false) }

      it "renders the empty state for no credit account" do
        get new_web_customer_payment_path(no_credit_customer)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Sin cuenta corriente")
      end
    end

    context "when customer has no pending orders" do
      it "renders the empty state for all paid up" do
        get new_web_customer_payment_path(customer)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Todo al día")
      end
    end
  end

  describe "POST /web/customers/:id/payments" do
    let!(:order_a) do
      Sales::CreateOrder.call(
        customer: customer,
        items: [ { product_id: product.id, quantity: 2, unit_price: 100 } ],
        order_type: "credit"
      ).record
    end

    let!(:order_b) do
      Sales::CreateOrder.call(
        customer: customer,
        items: [ { product_id: product.id, quantity: 3, unit_price: 100 } ],
        order_type: "credit"
      ).record
    end

    context "with valid single-method input" do
      it "creates one Payment and two Allocations, then redirects to customer show" do
        expect {
          post web_customer_payments_path(customer), params: {
            payment_date: Date.today.iso8601,
            notes: "Pago semanal",
            allocations: {
              "0" => { order_id: order_a.id, include: "1", amount: "200", payment_method: "cash" },
              "1" => { order_id: order_b.id, include: "1", amount: "150", payment_method: "cash" }
            }
          }
        }.to change(Payment, :count).by(1)
         .and change(PaymentAllocation, :count).by(2)

        expect(response).to redirect_to(web_customer_path(customer))
        follow_redirect!
        expect(response.body).to include("Cobro de $350")
      end
    end

    context "with mixed methods" do
      it "creates one Payment per method group" do
        expect {
          post web_customer_payments_path(customer), params: {
            allocations: {
              "0" => { order_id: order_a.id, include: "1", amount: "200", payment_method: "cash" },
              "1" => { order_id: order_b.id, include: "1", amount: "150", payment_method: "transfer" }
            }
          }
        }.to change(Payment, :count).by(2)
         .and change(PaymentAllocation, :count).by(2)
      end
    end

    context "with unchecked rows" do
      it "ignores rows with include != '1'" do
        expect {
          post web_customer_payments_path(customer), params: {
            allocations: {
              "0" => { order_id: order_a.id, include: "1", amount: "200", payment_method: "cash" },
              "1" => { order_id: order_b.id, include: "0", amount: "", payment_method: "cash" }
            }
          }
        }.to change(Payment, :count).by(1)
         .and change(PaymentAllocation, :count).by(1)
      end
    end

    context "with invalid input — amount exceeds outstanding" do
      it "re-renders the form with an error and creates nothing" do
        expect {
          post web_customer_payments_path(customer), params: {
            allocations: {
              "0" => { order_id: order_a.id, include: "1", amount: "9999", payment_method: "cash" }
            }
          }
        }.to change(Payment, :count).by(0)
         .and change(PaymentAllocation, :count).by(0)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to match(/saldo pendiente/i)
      end
    end

    context "with no rows checked" do
      it "returns an error" do
        post web_customer_payments_path(customer), params: {
          allocations: {
            "0" => { order_id: order_a.id, include: "0", amount: "0", payment_method: "cash" }
          }
        }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to match(/al menos una orden/i)
      end
    end
  end
end
