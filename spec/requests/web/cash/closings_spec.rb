# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Web::Cash::Closings", type: :request do
  let(:admin) { create(:user, role: "admin") }
  let(:date)  { Date.new(2026, 8, 3) }

  def post_closing(params)
    post "/web/cash/days/#{date}/closing", params: params
  end

  describe "GET /web/cash/days/:day_business_date/closing/new" do
    before { sign_in admin }

    def get_new
      get "/web/cash/days/#{date}/closing/new"
    end

    it "shows the expected amount and how many movements the day has" do
      create(:cash_movement, business_date: date, amount: 311_700)
      create(:cash_movement, :store_expense, business_date: date)

      get_new

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Esperado en el cajón")
      expect(response.body).to include("298.700,00")
      expect(response.body).to include("El día tiene 2 movimientos.")
    end

    it "renders the open day behind the modal, list and entry form included" do
      movement = create(:cash_movement, business_date: date, description: "Mostrador")

      get_new

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="day-entry-form"', 'id="day-entries"', %(id="entry_#{movement.id}"))
    end

    it "warns about the day's uncollected sale notes" do
      create(:order, :pending, :invoice_b, sale_date: date)

      get_new

      expect(response.body).to include("1 nota de pedido sin cobrar")
    end

    it "warns about the day's sales with no invoice type assigned" do
      create(:order, sale_date: date, invoice_type: nil)

      get_new

      expect(response.body).to include("1 venta sin tipo de factura asignado")
    end

    it "shows neither warning when the day is complete" do
      create(:order, :invoice_b, sale_date: date)
      create(:order, :pending, :invoice_b, sale_date: date + 1)

      get_new

      expect(response.body).not_to include("sin cobrar")
      expect(response.body).not_to include("sin tipo de factura")
    end

    it "never shows a negative expectation" do
      create(:cash_movement, :store_expense, business_date: date, amount: -300_000)

      get_new

      expect(response.body).to include("El cajón no alcanzó: los fajos pusieron $300.000,00.")
      expect(response.body).to include("A envolver: $0,00.")
      expect(response.body).not_to include("Esperado en el cajón")
    end

    it "shows what the app recorded for each digital arca" do
      create(:cash_movement, :card_sale, business_date: date, amount: 54_700)
      create(:cash_movement, business_date: date, channel: "mercado_pago", account: "mercado_pago", amount: 21_300)

      get_new

      expect(response.body).to include("Lote Payway")
      expect(response.body).to include("54.700,00")
      expect(response.body).to include("Mercado Pago")
      expect(response.body).to include("21.300,00")
    end
  end

  describe "POST /web/cash/days/:day_business_date/closing" do
    before { sign_in admin }

    it "closes the day and seals its movements" do
      movement = create(:cash_movement, business_date: date, amount: 311_700)

      post_closing(counted_cash: "311.700,00")

      expect(response).to redirect_to(web_cash_day_path(date))
      expect(DailyClosing.exists?(business_date: date)).to be true
      expect(movement.reload.daily_closing_id).to be_present
    end

    it "accepts an amount in Argentine format" do
      create(:cash_movement, business_date: date, amount: 311_700)

      post_closing(counted_cash: "311.700,00")

      expect(DailyClosing.find_by(business_date: date).counted_cash).to eq(311_700)
    end

    it "refuses a non-numeric amount and writes nothing" do
      create(:cash_movement, business_date: date, amount: 311_700)

      expect {
        post_closing(counted_cash: "abc")
      }.not_to change(DailyClosing, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include('id="day-entry-form"', 'id="day-entries"')
    end

    it "refuses to close an already-closed day and writes nothing" do
      create(:daily_closing, business_date: date)

      expect {
        post_closing(counted_cash: "0,00")
      }.not_to change(DailyClosing, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "authorization" do
    it "turns the cashier away: the closing flow is admin-only for now" do
      sign_in create(:user, role: "caja")

      expect {
        post_closing(counted_cash: "0,00")
      }.not_to change(DailyClosing, :count)

      expect(response).to redirect_to(authenticated_root_path)
      expect(flash[:alert]).to be_present
    end

    it "turns a seller away" do
      sign_in create(:user, role: "vendedor")

      post_closing(counted_cash: "0,00")

      expect(response).to redirect_to(authenticated_root_path)
    end
  end
end
