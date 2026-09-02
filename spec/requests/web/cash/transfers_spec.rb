# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Web::Cash::Transfers", type: :request do
  let(:cashier) { create(:user, role: "caja") }
  let(:date)    { "2026-08-03" }

  before { sign_in cashier }

  def post_transfer(params)
    post "/web/cash/transfers",
         params: { business_date: date }.merge(params),
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
  end

  def post_preview(params)
    post "/web/cash/transfers/preview",
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

    it "puts each leg in the zone its arca belongs to" do
      post_transfer(from: "drawer", to: "main_cash", amount: "10.000,00", description: "Cierre")

      expect(response.body).to include('target="drawer-rows"')
      expect(response.body).to include('target="arca-rows"')
    end

    it "puts both legs in the arca zone when no arca is the drawer" do
      post_transfer(from: "main_cash", to: "bank", amount: "10.000,00", description: "Depósito")

      expect(response.body).not_to include('target="drawer-rows"')
      expect(response.body.scan('target="arca-rows"').size).to eq(2)
    end

    it "refuses a transfer between the same arca and writes nothing" do
      expect {
        post_transfer(from: "bank", to: "bank", amount: "10.000,00")
      }.not_to change(CashMovement, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("arcas distintas")
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
    # the same way the two live rows do. What must never happen is 1.500 being
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
  end

  describe "POST /web/cash/transfers/preview" do
    it "shows both legs without writing anything" do
      expect {
        post_preview(from: "main_cash", to: "bank", amount: "150.000,00", description: "Depósito")
      }.not_to change(CashMovement, :count)

      expect(response.body).to include('target="transfer-preview"')
      expect(response.body).to include("Caja grande", "Banco", "150.000,00")
    end

    it "shows the same arcas and amounts the confirmation writes" do
      params = { from: "mercado_pago", to: "bank", amount: "150.000,00", description: "Para proveedores" }

      post_preview(params)
      previewed = response.body

      post_transfer(params)

      legs = CashMovement.order(:id).last(2)
      expect(legs.map { |leg| leg.amount.abs }.uniq).to eq([ 150_000 ])
      legs.each { |leg| expect(previewed).to include(CashMovement.account_label(leg.account)) }
      expect(previewed).to include("150.000,00")
    end

    it "refuses to preview a transfer between the same arca" do
      expect {
        post_preview(from: "bank", to: "bank", amount: "10.000,00")
      }.not_to change(CashMovement, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("arcas distintas")
    end

    it "refuses to preview an unparseable amount" do
      post_preview(from: "main_cash", to: "bank", amount: "abc")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("mayor a cero")
    end

    it "refuses to preview a closed day" do
      create(:daily_closing, business_date: Date.new(2026, 8, 3))

      post_preview(from: "main_cash", to: "bank", amount: "10.000,00")

      expect(response).to redirect_to("/web/cash/days/#{date}")
    end

    it "turns a seller away" do
      sign_in create(:user, role: "vendedor")

      post_preview(from: "main_cash", to: "bank", amount: "10.000,00")

      expect(response).not_to have_http_status(:ok)
    end
  end

  describe "the day screen" do
    it "offers the transfer form on an open day" do
      get "/web/cash/days/#{date}"

      expect(response.body).to include("Movimiento entre arcas")
      expect(response.body).to include("transfer-panel")
    end

    it "offers no transfer form on a closed day" do
      create(:daily_closing, business_date: Date.new(2026, 8, 3))

      get "/web/cash/days/#{date}"

      expect(response.body).not_to include("transfer-panel")
    end
  end
end
