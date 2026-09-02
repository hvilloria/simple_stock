# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Web::Cash::Days", type: :request do
  let(:cashier) { create(:user, role: "caja") }
  let(:date)    { Date.new(2026, 8, 3) }

  describe "GET /web/cash/days" do
    it "sends the cashier to today" do
      sign_in cashier

      get "/web/cash/days"

      expect(response).to redirect_to("/web/cash/days/#{Date.current}")
    end
  end

  describe "GET /web/cash/days/:business_date" do
    before { sign_in cashier }

    it "renders the day's drawer movements" do
      create(:cash_movement, business_date: date, description: "Venta mostrador")

      get "/web/cash/days/2026-08-03"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Venta mostrador")
    end

    it "does not render another day's movements" do
      create(:cash_movement, business_date: date + 1, description: "De otro día")

      get "/web/cash/days/2026-08-03"

      expect(response.body).not_to include("De otro día")
    end

    it "does not render an arca-zone movement" do
      create(:cash_movement, :supplier_payment, business_date: date, description: "Cromosol")

      get "/web/cash/days/2026-08-03"

      expect(response.body).not_to include("Cromosol")
    end

    it "falls back to today when the date is not a date" do
      get "/web/cash/days/no-es-fecha"

      expect(response).to redirect_to("/web/cash/days/#{Date.current}")
    end

    it "shows the sales-by-channel panel with a channel's total and the amount to wrap" do
      create(:cash_movement, business_date: date, channel: "cash", account: "drawer", amount: 324_700)
      create(:cash_movement, :store_expense, business_date: date)

      get "/web/cash/days/2026-08-03"

      expect(response.body).to include("Ventas por canal")
      expect(response.body).to include("Efectivo")
      expect(response.body).to include("324.700,00")
      expect(response.body).to include("Monto a fajar")
      expect(response.body).to include("311.700,00")
    end
  end

  describe "POST /web/cash/movements" do
    before { sign_in cashier }

    it "includes the sales-by-channel panel in the turbo stream response" do
      post "/web/cash/movements",
           params: { business_date: date, category: "sale", channel: "cash",
                     description: "Venta mostrador", amount: "1.000,00" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response.body).to include('target="sales-by-channel"')
      expect(response.body).to include("Ventas por canal")
    end
  end

  describe "authorization" do
    it "turns a seller away" do
      sign_in create(:user, role: "vendedor")

      get "/web/cash/days/2026-08-03"

      expect(response).to redirect_to(authenticated_root_path)
    end

    it "sends an anonymous visitor to the login" do
      get "/web/cash/days/2026-08-03"

      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "a closed day" do
    before do
      sign_in cashier
      create(:cash_movement, business_date: date, description: "Venta mostrador")
      create(:daily_closing, business_date: date)

      get "/web/cash/days/2026-08-03"
    end

    it "says so" do
      expect(response.body).to include("Día cerrado")
    end

    it "still shows the day's movements" do
      expect(response.body).to include("Venta mostrador")
    end

    it "offers no live row" do
      expect(response.body).not_to include("drawer-live-row")
    end

    it "offers no way to correct a row" do
      expect(response.body).not_to include("Editar")
      expect(response.body).not_to include("Eliminar")
    end
  end

  describe "a row born from a collection" do
    before { sign_in cashier }

    it "offers no way to correct it" do
      create(:cash_movement, :from_collection, business_date: date, description: "Cobro a cuenta")

      get "/web/cash/days/2026-08-03"

      expect(response.body).to include("Cobro a cuenta")
      expect(response.body).not_to include("Editar")
      expect(response.body).not_to include("Eliminar")
    end

    it "offers them on a row the cashier typed the same day" do
      create(:cash_movement, business_date: date, description: "Venta mostrador")

      get "/web/cash/days/2026-08-03"

      expect(response.body).to include("Editar")
      expect(response.body).to include("Eliminar")
    end

    it "marks the row's origin" do
      create(:cash_movement, :from_collection, business_date: date, description: "Cobro a cuenta")

      get "/web/cash/days/2026-08-03"

      expect(response.body).to include("Automático")
    end

    it "leaves a typed row unmarked" do
      create(:cash_movement, business_date: date, description: "Venta mostrador")

      get "/web/cash/days/2026-08-03"

      expect(response.body).not_to include("Automático")
    end
  end

  describe "an open day" do
    before do
      sign_in cashier
      create(:cash_movement, business_date: date, description: "Venta mostrador")

      get "/web/cash/days/2026-08-03"
    end

    it "offers the live row" do
      expect(response.body).to include("drawer-live-row")
    end

    it "offers the correction affordances" do
      expect(response.body).to include("Editar")
      expect(response.body).to include("Eliminar")
    end
  end
end
