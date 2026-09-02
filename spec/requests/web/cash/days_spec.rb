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
end
