# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Web::Orders", type: :request do
  let!(:stock_location) { create(:stock_location) }
  let(:vendedor) { create(:user, role: "vendedor") }
  let(:customer_with_credit) { create(:customer, :with_credit) }
  let(:product) { create(:product, current_stock: 50, price_unit: 100) }

  before { sign_in vendedor }

  describe "GET /web/orders" do
    it "orders same-day notes by created_at desc (tie-break)" do
      same_date = Date.current
      create(:order, :pending, order_type: "immediate",
             paper_number: "AAA", sale_date: same_date,
             total_amount: 100, original_total_amount: 100,
             created_at: 2.hours.ago)
      create(:order, :pending, order_type: "immediate",
             paper_number: "BBB", sale_date: same_date,
             total_amount: 100, original_total_amount: 100,
             created_at: 1.hour.ago)

      get "/web/orders"
      expect(response).to have_http_status(:ok)
      expect(response.body.index("#BBB")).to be < response.body.index("#AAA")
    end
  end

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
        sale_date: Date.current.iso8601,
        paper_number: "0099"
      }
    end

    context "credit sale note" do
      it "creates a pending Order with no Payment captured" do
        expect {
          post "/web/orders", params: base_params
        }.to change(Order, :count).by(1)
          .and change(Payment, :count).by(0)
          .and change(PaymentAllocation, :count).by(0)

        order = Order.order(:created_at).last
        expect(order.status).to eq("pending")
        expect(order.order_type).to eq("credit")
        expect(order.paper_number).to eq("0099")
        expect(order.total_amount.to_f).to eq(200.0)
        expect(order.original_total_amount.to_f).to eq(200.0)
        expect(order.order_items.first.discount_percent.to_i).to eq(0)
      end
    end

    context "immediate sale note" do
      it "creates a pending Order without requiring a payment at creation" do
        retail = create(:customer, has_credit_account: false, name: "Walk-in")
        params = base_params.deep_merge(
          order: { customer_id: retail.id, order_type: "immediate" }
        )

        expect {
          post "/web/orders", params: params
        }.to change(Order, :count).by(1)
          .and change(Payment, :count).by(0)

        order = Order.order(:created_at).last
        expect(order.status).to eq("pending")
        expect(order.order_type).to eq("immediate")
      end
    end

    context "on_account sale note" do
      it "creates an on_account order with contact and initial delivery" do
        retail = create(:customer, has_credit_account: false, name: "Walk-in")
        params = base_params.deep_merge(
          order: { customer_id: retail.id, order_type: "on_account" }
        ).merge(
          contact_name: "Juan Pérez",
          contact_phone: "11 5555 1234",
          delivered_product_ids: [ product.id ]
        )

        expect {
          post "/web/orders", params: params
        }.to change(Order.on_account, :count).by(1)

        order = Order.on_account.order(:created_at).last
        expect(order.contact_name).to eq("Juan Pérez")
        # contact_phone is normalized to digits only in Order#normalize_contact_phone (pending #12)
        expect(order.contact_phone).to eq("1155551234")
        expect(order.order_items.first.delivered_at).to be_present
      end
    end

    context "without paper_number" do
      it "fails and renders new" do
        params = base_params.merge(paper_number: nil)

        expect {
          post "/web/orders", params: params
        }.not_to change(Order, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "credit sale to a customer without credit account" do
      it "fails and renders new" do
        retail = create(:customer, has_credit_account: false, name: "Walk-in")
        params = base_params.deep_merge(order: { customer_id: retail.id })

        expect {
          post "/web/orders", params: params
        }.not_to change(Order, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "redirects" do
      it "sends the user to the created note's show page" do
        post "/web/orders", params: base_params
        order = Order.order(:created_at).last
        expect(response).to redirect_to(web_order_path(order))
      end
    end
  end
end
