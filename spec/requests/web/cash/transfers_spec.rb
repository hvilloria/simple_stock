# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Web::Cash::Transfers", type: :request do
  let(:admin) { create(:user, role: "admin") }
  let(:date)  { "2026-08-03" }

  before { sign_in admin }

  def post_transfer(params)
    post "/web/cash/transfers",
         params: { business_date: date }.merge(params),
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
  end

  describe "POST /web/cash/transfers" do
    it "writes exactly two legs tied by one transfer_group_id" do
      expect {
        post_transfer(from: "mercado_pago", to: "bank", amount: "150.000,00", description: "Para proveedores")
      }.to change(CashMovement, :count).by(2)

      legs = CashMovement.order(:id).last(2)
      expect(legs.map(&:transfer_group_id).uniq.size).to eq(1)
      expect(legs.map(&:category).uniq).to eq([ "internal_transfer" ])
      expect(legs.map { |leg| [ leg.account, leg.amount ] })
        .to match_array([ [ "mercado_pago", -150_000 ], [ "bank", 150_000 ] ])
      expect(legs.map(&:business_date).uniq).to eq([ Date.new(2026, 8, 3) ])
    end

    it "appends one folded row to the list, never two" do
      post_transfer(from: "mercado_pago", to: "bank", amount: "400.000,00")

      legs = CashMovement.order(:id).last(2)
      expect(response.body.scan('target="day-entries"').size).to eq(1)
      expect(response.body).to include(%(id="entry_#{legs.first.id}"), "Mercado Pago → Banco", "⇄")
      expect(response.body).not_to include(%(id="entry_#{legs.last.id}"))
    end

    it "marks the folded row when one leg is the drawer" do
      post_transfer(from: "drawer", to: "main_cash", amount: "10.000,00", description: "Cierre")

      expect(response.body).to include("Caja del día → Caja grande", "Cuenta en el cajón")
    end

    it "brings the form back on Entre arcas and repaints the sales panel" do
      post_transfer(from: "main_cash", to: "bank", amount: "10.000,00", description: "Depósito")

      expect(response.body).to include('action="replace"', 'target="day-entry-form"')
      expect(response.body).to include('data-cash-entry-mode-value="move"')
      expect(response.body).to include('target="sales-by-channel"')
      %w[drawer-rows drawer-live-row arca-rows arca-live-row].each do |old_id|
        expect(response.body).not_to include(old_id)
      end
    end

    it "refuses a transfer between the same arca and writes nothing" do
      expect {
        post_transfer(from: "bank", to: "bank", amount: "10.000,00")
      }.not_to change(CashMovement, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("arcas distintas")
      expect(response.body).to include('target="day-entry-form"')
      expect(response.body).not_to include('target="day-entries"')
    end

    it "refuses an unknown arca and writes nothing" do
      expect {
        post_transfer(from: "vault", to: "bank", amount: "10.000,00")
      }.not_to change(CashMovement, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "refuses an amount that is not a number and writes nothing" do
      expect {
        post_transfer(from: "main_cash", to: "bank", amount: "abc")
      }.not_to change(CashMovement, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "refuses a zero amount and writes nothing" do
      expect {
        post_transfer(from: "main_cash", to: "bank", amount: "0,00")
      }.not_to change(CashMovement, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "refuses a negative amount and writes nothing" do
      expect {
        post_transfer(from: "main_cash", to: "bank", amount: "-10.000,00")
      }.not_to change(CashMovement, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    # The module reads a single-separator thousands string as Argentine format,
    # the same way the entry row does. What must never happen is 1.500 being
    # read as one and a half pesos.
    it "reads a thousands-separated amount as thousands, never as a decimal" do
      post_transfer(from: "main_cash", to: "bank", amount: "1.500")

      expect(CashMovement.order(:id).last.amount).to eq(1_500)
    end

    it "refuses to write into a closed day" do
      create(:daily_closing, business_date: Date.new(2026, 8, 3))

      expect {
        post_transfer(from: "main_cash", to: "bank", amount: "10.000,00")
      }.not_to change(CashMovement, :count)
    end

    it "turns a seller away" do
      sign_in create(:user, role: "vendedor")

      expect {
        post_transfer(from: "main_cash", to: "bank", amount: "10.000,00")
      }.not_to change(CashMovement, :count)
    end

    it "turns the cashier away: the module is admin-only for now" do
      sign_in create(:user, role: "caja")

      expect {
        post_transfer(from: "main_cash", to: "bank", amount: "10.000,00")
      }.not_to change(CashMovement, :count)

      expect(response).to redirect_to(authenticated_root_path)
      expect(flash[:alert]).to be_present
    end
  end

  describe "the day screen" do
    it "offers the transfer form on an open day" do
      get "/web/cash/days/#{date}"

      expect(response.body).to include("⇄ Entre arcas")
      expect(response.body).to include('action="/web/cash/transfers"')
    end

    it "offers no transfer form on a closed day" do
      create(:daily_closing, business_date: Date.new(2026, 8, 3))

      get "/web/cash/days/#{date}"

      expect(response.body).not_to include("⇄ Entre arcas")
      expect(response.body).not_to include('action="/web/cash/transfers"')
    end
  end
end
