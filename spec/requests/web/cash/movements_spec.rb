# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Web::Cash::Movements", type: :request do
  let(:cashier) { create(:user, role: "caja") }
  let(:date)    { "2026-08-03" }

  before { sign_in cashier }

  def post_movement(params)
    post "/web/cash/movements",
         params: { business_date: date }.merge(params),
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
  end

  describe "POST /web/cash/movements" do
    it "records a cash sale against the drawer" do
      post_movement(category: "sale", channel: "cash", description: "Venta mostrador", amount: "324.700,00")

      movement = CashMovement.last
      expect(movement.category).to eq("sale")
      expect(movement.account).to eq("drawer")
      expect(movement.amount).to eq(324_700)
      expect(movement.business_date).to eq(Date.new(2026, 8, 3))
    end

    it "routes a card sale to the bank without asking" do
      post_movement(category: "sale", channel: "card", description: "Venta tarjeta", amount: "54.700,00")

      expect(CashMovement.last.account).to eq("bank")
    end

    it "records an expense as an outflow from the drawer" do
      post_movement(category: "fixed_expense", subcategory: "store_expenses", description: "Bolsas", amount: "13.000,00")

      movement = CashMovement.last
      expect(movement.amount).to eq(-13_000)
      expect(movement.account).to eq("drawer")
    end

    it "answers with a turbo stream that appends the row" do
      post_movement(category: "sale", channel: "cash", description: "Venta mostrador", amount: "1.000,00")

      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include('action="append"', 'target="drawer-rows"')
      expect(response.body).to include('target="drawer-live-row"')
    end

    it "refuses an amount that is not a number and writes nothing" do
      expect {
        post_movement(category: "sale", channel: "cash", description: "Venta", amount: "abc")
      }.not_to change(CashMovement, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "refuses a sale with no channel" do
      expect {
        post_movement(category: "sale", channel: "", description: "Venta", amount: "1.000,00")
      }.not_to change(CashMovement, :count)
    end

    it "refuses a category the drawer zone does not offer" do
      expect {
        post_movement(category: "partner", description: "Retiro", amount: "1.000,00")
      }.not_to change(CashMovement, :count)
    end

    it "refuses to write into a closed day" do
      create(:daily_closing, business_date: Date.new(2026, 8, 3))

      expect {
        post_movement(category: "sale", channel: "cash", description: "Tarde", amount: "1.000,00")
      }.not_to change(CashMovement, :count)
    end

    it "turns a seller away" do
      sign_in create(:user, role: "vendedor")

      expect {
        post_movement(category: "sale", channel: "cash", description: "Venta", amount: "1.000,00")
      }.not_to change(CashMovement, :count)
    end
  end

  describe "every category the drawer zone offers" do
    it "loads each one end to end" do
      post_movement(category: "sale", channel: "cash", description: "Venta", amount: "1.000,00")
      post_movement(category: "suppliers", description: "Cromosol", amount: "2.000,00")
      post_movement(category: "fixed_expense", subcategory: "store_expenses", description: "Bolsas", amount: "3.000,00")

      expect(CashMovement.pluck(:category)).to contain_exactly("sale", "suppliers", "fixed_expense")
    end

    it "refuses a fixed expense with no subcategory, which is why the row offers one" do
      expect {
        post_movement(category: "fixed_expense", description: "Bolsas", amount: "3.000,00")
      }.not_to change(CashMovement, :count)
    end

    it "refuses a subcategory on a category that is not a fixed expense" do
      expect {
        post_movement(category: "suppliers", subcategory: "store_expenses", description: "Cromosol", amount: "2.000,00")
      }.not_to change(CashMovement, :count)
    end
  end
end
