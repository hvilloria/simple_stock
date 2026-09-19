# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Web::Dashboard", type: :request do
  let(:admin)   { create(:user, :admin) }
  let(:cashier) { create(:user, :caja) }

  around do |example|
    travel_to(Date.new(2026, 9, 19)) { example.run }
  end

  def movement(*traits, **attrs)
    create(:cash_movement, *traits, { business_date: Date.new(2026, 9, 3) }.merge(attrs))
  end

  def block
    Nokogiri::HTML(response.body).at("#cash-month")
  end

  def figure(name)
    block.at("[data-figure=#{name}]").text.strip
  end

  describe "GET /web/dashboard" do
    before do
      movement(amount: 300_000)
      movement(:card_sale, amount: 50_000)
      movement(:compensation_sale, amount: 661_188)
      movement(account: "usd", channel: "usd", amount: 500)
      movement(:store_expense, subcategory: "salaries", amount: -900_000, account: "bank")
      movement(:store_expense, subcategory: "rent", amount: -2_300, account: "usd")
    end

    it "shows the admin the month's cash block, dollars apart" do
      sign_in admin
      get web_dashboard_path

      expect(response).to have_http_status(:ok)
      expect(block.at("h3").text.strip).to eq("Caja de septiembre")
      expect(figure("sold_total")).to eq("$ 1.011.188")
      expect(figure("sold_efectivo")).to eq("$ 300.000")
      expect(figure("sold_banco")).to eq("$ 50.000")
      expect(figure("sold_compensation")).to eq("$ 661.188")
      expect(figure("sold_usd")).to eq("US$ 500")
      expect(figure("fixed_total")).to eq("$ 900.000")
      expect(figure("fixed_salaries")).to eq("$ 900.000")
      expect(figure("fixed_usd")).to eq("US$ 2.300")
    end

    it "does not show the block to a cashier, who still sees her dashboard" do
      expect(Cash::Reports::MonthQuery).not_to receive(:new)
      sign_in cashier
      get web_dashboard_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Ventas de Hoy")
      expect(block).to be_nil
      expect(response.body).not_to include("Caja de septiembre")
    end
  end

  describe "month navigation" do
    before { sign_in admin }

    it "links the current month to the previous one and to no next one" do
      get web_dashboard_path

      expect(block.at("a[rel=prev]")["href"]).to eq(web_dashboard_path(month: "2026-08"))
      expect(block.at("a[rel=next]")).to be_nil
    end

    it "shows a past month's figures and links back to the following one" do
      movement(amount: 70_000, business_date: Date.new(2026, 8, 20))

      get web_dashboard_path(month: "2026-08")

      expect(block.at("h3").text.strip).to eq("Caja de agosto")
      expect(figure("sold_total")).to eq("$ 70.000")
      expect(block.at("a[rel=prev]")["href"]).to eq(web_dashboard_path(month: "2026-07"))
      expect(block.at("a[rel=next]")["href"]).to eq(web_dashboard_path(month: "2026-09"))
    end

    it "leaves out the dollar and compensation lines when there are none" do
      get web_dashboard_path(month: "2026-08")

      expect(block.at("[data-figure=sold_usd]")).to be_nil
      expect(block.at("[data-figure=sold_compensation]")).to be_nil
      expect(block.at("[data-figure=fixed_usd]")).to be_nil
    end

    it "falls back to the current month on an unparseable value" do
      get web_dashboard_path(month: "not-a-month")

      expect(block.at("h3").text.strip).to eq("Caja de septiembre")
    end

    it "falls back to the current month on a malformed parameter" do
      get "/web/dashboard?month[]=2026-08"

      expect(block.at("h3").text.strip).to eq("Caja de septiembre")
    end

    it "does not go past the current month" do
      get web_dashboard_path(month: "2026-11")

      expect(block.at("h3").text.strip).to eq("Caja de septiembre")
      expect(block.at("a[rel=next]")).to be_nil
    end
  end
end
