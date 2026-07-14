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

  # Money values POSTed straight at the endpoint, bypassing Stimulus. The backend must
  # normalize correctly or reject — never book a wrong number, never drop the row.
  describe "POST /web/orders — hostile unit_price" do
    def post_price(unit_price)
      post "/web/orders", params: {
        order: { customer_id: customer_with_credit.id, order_type: "credit", channel: "counter" },
        purchase_items: [ { product_id: product.id, quantity: "2", unit_price: unit_price } ],
        sale_date: Date.current.iso8601,
        paper_number: "0099"
      }
    end

    def last_item
      Order.order(:created_at).last.order_items.first
    end

    it "persists 1500000.50 for the Argentine format '1.500.000,50'" do
      expect { post_price("1.500.000,50") }.to change(Order, :count).by(1)

      expect(last_item.unit_price).to eq(BigDecimal("1500000.50"))
      expect(Order.order(:created_at).last.total_amount).to eq(BigDecimal("3000001.00"))
    end

    it "persists 1500000 for the Argentine thousands '1.500.000'" do
      expect { post_price("1.500.000") }.to change(Order, :count).by(1)

      expect(last_item.unit_price).to eq(1_500_000)
    end

    it "persists 1500.50 for the clean decimal '1500.50'" do
      expect { post_price("1500.50") }.to change(Order, :count).by(1)

      expect(last_item.unit_price).to eq(BigDecimal("1500.50"))
    end

    it "rejects a non-numeric price instead of booking zero" do
      expect { post_price("abc") }.not_to change(Order, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "rejects a negative price" do
      expect { post_price("-500") }.not_to change(Order, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "rejects a blank price" do
      expect { post_price("") }.not_to change(Order, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "GET /web/orders/:id" do
    it "renders the order show page after its product is soft-deleted" do
      admin = create(:user, role: "admin")
      historical_product = create(:product, name: "Pieza histórica")
      order = create(:order, status: "confirmed")
      create(:order_item, order: order, product: historical_product, quantity: 1, unit_price: 100)
      historical_product.destroy # soft delete
      sign_in admin

      get web_order_path(order)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Pieza histórica")
    end
  end
end
