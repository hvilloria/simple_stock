# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Web::Orders", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let!(:stock_location) { create(:stock_location) }
  let(:vendedor) { create(:user, role: "vendedor") }
  let(:customer_with_credit) { create(:customer, :with_credit) }
  let(:product) { create(:product, current_stock: 50, price_unit: 100) }

  before { sign_in vendedor }

  describe "GET /web/orders" do
    it "orders same-day pending notes newest first" do
      same_date = Date.current
      create(:order, :pending, order_type: "immediate",
             paper_number: "AAA", sale_date: same_date,
             total_amount: 100, original_total_amount: 100)
      create(:order, :pending, order_type: "immediate",
             paper_number: "BBB", sale_date: same_date,
             total_amount: 100, original_total_amount: 100)

      get "/web/orders", params: { status: "pending" }

      expect(response).to have_http_status(:ok)
      expect(response.body.index("#BBB")).to be < response.body.index("#AAA")
    end

    let(:credit_customer) { create(:customer, :with_credit) }

    def collected_order(paper:, sold:, collected:)
      order = create(:order, :credit_order, :pending, customer: credit_customer,
                     paper_number: paper, sale_date: sold,
                     total_amount: 100, original_total_amount: 100)
      payment = create(:payment, customer: credit_customer, amount: 100,
                       payment_date: collected)
      create(:payment_allocation, payment: payment, order: order, amount: 100)
      order.refresh_status_from_balance!
      order
    end

    it "puts an old sale collected today at the top" do
      # Anchored on a fixed Thursday so OLD's and NEW's collected dates both
      # land inside "Esta semana" (Monday..Sunday) regardless of the real
      # weekday the suite runs on.
      travel_to Date.new(2026, 7, 30) do
        collected_order(paper: "OLD", sold: Date.current - 5.days, collected: Date.current)
        collected_order(paper: "NEW", sold: Date.current - 1.day,
                        collected: Date.current - 1.day)

        get "/web/orders"

        expect(response.body.index("#OLD")).to be < response.body.index("#NEW")
      end
    end

    it "sorts pending sales by sale date, not by collection" do
      # Anchored on a fixed Thursday so P1's sale_date lands inside "Esta
      # semana" (Monday..Sunday) regardless of the real weekday the suite
      # runs on.
      travel_to Date.new(2026, 7, 30) do
        # P2 (newer sale_date) is created FIRST so its id is lower than P1's.
        # This makes `id DESC` alone yield the wrong order, so the assertion
        # only passes under a genuine `sale_date DESC` primary sort.
        create(:order, :pending, paper_number: "P2", sale_date: Date.current,
               total_amount: 100, original_total_amount: 100)
        create(:order, :pending, paper_number: "P1", sale_date: Date.current - 2.days,
               total_amount: 100, original_total_amount: 100)

        get "/web/orders", params: { status: "pending" }

        expect(response.body.index("#P2")).to be < response.body.index("#P1")
      end
    end

    it "narrows by type" do
      create(:order, :on_account, paper_number: "ACC", sale_date: Date.current,
             total_amount: 100, original_total_amount: 100)
      create(:order, :pending, paper_number: "IMM", sale_date: Date.current,
             total_amount: 100, original_total_amount: 100)

      get "/web/orders", params: { status: "pending", type: "on_account" }

      expect(response.body).to include("#ACC")
      expect(response.body).not_to include("#IMM")
    end

    it "ignores every other filter when searching by paper number" do
      collected_order(paper: "7788", sold: Date.current - 90.days,
                      collected: Date.current - 90.days)

      get "/web/orders", params: { paper_number: "7788", status: "pending",
                                   type: "immediate", period: "today" }

      expect(response.body).to include("#7788")
    end

    it "ignores the period under Todas" do
      create(:order, :pending, paper_number: "OLDP", sale_date: Date.current - 90.days,
             total_amount: 100, original_total_amount: 100)

      get "/web/orders", params: { status: "", period: "this_week" }

      expect(response.body).to include("#OLDP")
    end

    it "excludes sales outside the selected period" do
      collected_order(paper: "FAR", sold: Date.current - 90.days,
                      collected: Date.current - 90.days)

      get "/web/orders", params: { period: "today" }

      expect(response.body).not_to include("#FAR")
    end

    it "falls back to the default period on an unrecognised value" do
      collected_order(paper: "GARBPER", sold: Date.current - 90.days, collected: Date.current - 90.days)

      get "/web/orders", params: { period: "not-a-period" }

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("#GARBPER")
    end

    it "paginates without repeating rows across pages" do
      # Papers are created in ascending order, so their ids ascend too. All 25
      # share settled_on == Date.current, so with the tie the ordering is fully
      # determined by `id DESC` — asserting the exact sequence (not just set
      # membership) is what actually exercises that tiebreaker.
      papers = (1..25).map { |n| format("D%03d", n) }
      papers.each { |p| collected_order(paper: p, sold: Date.current, collected: Date.current) }

      get "/web/orders", params: { period: "today" }
      first_page = response.body.scan(/#(D\d{3})/).flatten

      get "/web/orders", params: { period: "today", page: 2 }
      second_page = response.body.scan(/#(D\d{3})/).flatten

      expect(first_page).to eq(papers.last(20).reverse)
      expect(second_page).to eq(papers.first(5).reverse)
    end

    it "labels the date column by the active axis" do
      collected_order(paper: "COL", sold: Date.current, collected: Date.current)
      get "/web/orders"
      expect(response.body).to include("Cobrada el")

      create(:order, :pending, paper_number: "PEN", sale_date: Date.current,
             total_amount: 100, original_total_amount: 100)
      get "/web/orders", params: { status: "pending" }
      expect(response.body).to include("Fecha venta")
    end

    it "shows the collected date as an extra column under Todas, with a dash when absent" do
      create(:order, :pending, paper_number: "NOPAY", sale_date: Date.current,
             total_amount: 100, original_total_amount: 100)

      get "/web/orders", params: { status: "" }

      expect(response.body).to include("Fecha venta")
      expect(response.body).to include("Cobrada el")
    end

    it "announces search mode" do
      get "/web/orders", params: { paper_number: "7788" }

      expect(response.body).to include("todo el historial")
    end

    it "renders the filtered empty state, not the generic one" do
      get "/web/orders", params: { status: "cancelled", period: "today" }

      expect(response.body).to include("No hay ventas con esos filtros")
    end

    it "treats a garbage status the same as Todas" do
      create(:order, :pending, paper_number: "GARB", sale_date: Date.current - 90.days,
             total_amount: 100, original_total_amount: 100)

      get "/web/orders", params: { status: "not-a-status" }
      garbage_body = response.body

      get "/web/orders", params: { status: "" }
      todas_body = response.body

      expect(garbage_body).to include("#GARB")
      expect(garbage_body).to include("Fecha venta")
      expect(garbage_body).to include("Cobrada el")
      expect(todas_body).to include("#GARB")
    end
  end

  describe "Cancelar visibility" do
    let(:admin) { create(:user, role: "admin") }
    let(:caja) { create(:user, role: "caja") }
    let(:credit_customer) { create(:customer, :with_credit) }

    def collected_order
      order = create(:order, :credit_order, :pending, customer: credit_customer,
                     paper_number: "GATE", total_amount: 100, original_total_amount: 100)
      payment = create(:payment, customer: credit_customer, amount: 100)
      create(:payment_allocation, payment: payment, order: order, amount: 100)
      order.refresh_status_from_balance!
      order
    end

    it "offers it to an admin on a collected sale" do
      collected_order
      sign_in admin

      get "/web/orders"

      expect(response.body).to include("Cancelar")
    end

    it "hides it from caja on a collected sale" do
      collected_order
      sign_in caja

      get "/web/orders"

      expect(response.body).not_to include("Cancelar")
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

    it "calls a collected sale 'Cobrada'" do
      order = create(:order, paper_number: "SHOW1", total_amount: 100,
                     original_total_amount: 100)

      get "/web/orders/#{order.id}"

      expect(response.body).to include("Cobrada")
      expect(response.body).not_to include("Confirmada")
    end
  end
end
