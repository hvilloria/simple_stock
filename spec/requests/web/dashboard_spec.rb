# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Web::Dashboard", type: :request do
  let(:admin) { create(:user, role: "admin") }

  before { sign_in admin }

  describe "GET /web/dashboard" do
    it "renders for an authenticated user" do
      get web_dashboard_path

      expect(response).to have_http_status(:ok)
    end
  end

  describe "sales today" do
    it "sums active orders by created_at, not by sale_date" do
      create(:order, total_amount: 1_000)
      create(:order, total_amount: 234)
      create(:order, :cancelled, total_amount: 900)
      # Sold on paper today but loaded into the system yesterday: out of the metric.
      create(:order, total_amount: 7_000, sale_date: Date.current, created_at: 1.day.ago)

      get web_dashboard_path

      expect(response.body).to include("ARS 1.234")
    end
  end

  describe "accounts receivable" do
    it "sums the balance of customers with a credit account, net of allocations" do
      debtor = create(:customer, :with_credit, name: "Taller Deudor")
      order  = create(:order, :credit_order, customer: debtor, total_amount: 5_000)
      payment = create(:payment, customer: debtor, amount: 1_200)
      create(:payment_allocation, payment: payment, order: order, amount: 1_200)

      # Mostrador sale: no credit account, never enters the receivable.
      create(:order, total_amount: 800)

      get web_dashboard_path

      expect(response.body).to include("ARS 3.800")
      expect(response.body).to include("1 cliente con deuda")
    end

    it "shows everyone up to date when there is no credit debt" do
      create(:customer, :with_credit, name: "Taller Al Dia")

      get web_dashboard_path

      expect(response.body).to include("Todos al día")
    end
  end

  describe "low stock" do
    it "lists products under the threshold and leaves the rest out" do
      create(:product, name: "Pastilla Baja", current_stock: 3)
      create(:product, name: "Filtro Agotado", current_stock: 0)
      create(:product, name: "Correa Justa", current_stock: 4)
      create(:product, name: "Bujia Limite", current_stock: 5)
      create(:product, name: "Disco Lleno", current_stock: 10)

      get web_dashboard_path

      expect(response.body).to include("Pastilla Baja", "Filtro Agotado", "Correa Justa")
      expect(response.body).to include("Sin stock")
      expect(response.body).not_to include("Bujia Limite")
      expect(response.body).not_to include("Disco Lleno")
    end

    it "reports a healthy inventory when nothing is low" do
      create(:product, name: "Disco Lleno", current_stock: 10)

      get web_dashboard_path

      expect(response.body).to include("Todo el stock está en niveles normales")
    end
  end

  describe "recent orders" do
    it "shows the 5 most recent active orders, newest first" do
      6.times { |i| create(:order, total_amount: 101 + i, created_at: (6 - i).minutes.ago) }
      create(:order, :cancelled, total_amount: 999)

      get web_dashboard_path

      expect(response.body).to include("ARS 106", "ARS 102")
      expect(response.body).not_to include("ARS 101")
      expect(response.body).not_to include("ARS 999")
      expect(response.body.index("ARS 106")).to be < response.body.index("ARS 105")
    end

    it "shows an empty state when there are no orders" do
      get web_dashboard_path

      expect(response.body).to include("No hay ventas recientes")
    end
  end
end
