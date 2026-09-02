# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Web::Cash::Reports", type: :request do
  let(:admin)   { create(:user, :admin) }
  let(:cashier) { create(:user, :caja) }

  def movement(*traits, **attrs)
    create(:cash_movement, *traits, { business_date: Date.new(2026, 9, 3) }.merge(attrs))
  end

  describe "GET /web/cash/reports/balance" do
    context "as the admin" do
      before { sign_in admin }

      it "renders one row per reporting group and no grand total" do
        get "/web/cash/reports/balance"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Balance general")

        rows = Nokogiri::HTML(response.body).css("#balance-rows tr")
        expect(rows.size).to eq(4)
        expect(rows.map { |row| row.css("td").first.text.strip })
          .to eq([ "Efectivo", "Banco", "Mercado Pago", "USD" ])
      end

      it "shows the figures of the range, split by column" do
        travel_to Date.new(2026, 9, 2) do
          movement(:opening_balance, account: "main_cash", business_date: Date.new(2026, 8, 20),
                                     amount: 1_000_000)
          movement(amount: 324_700, account: "drawer", channel: "cash")
          movement(:store_expense, amount: -13_000)

          get "/web/cash/reports/balance"
        end

        expect(response.body).to include("1.000.000,00") # opening
        expect(response.body).to include("324.700,00")   # sales
        expect(response.body).to include("13.000,00")    # fixed expenses
        expect(response.body).to include("1.311.700,00") # closing
      end

      it "leaves out what falls outside the range" do
        travel_to Date.new(2026, 9, 2) do
          movement(business_date: Date.new(2026, 10, 5), amount: 777_777,
                   account: "drawer", channel: "cash")

          get "/web/cash/reports/balance"
        end

        expect(response.body).not_to include("777.777,00")
      end
    end

    context "as the cashier" do
      before { sign_in cashier }

      it "turns her away even when she types the URL" do
        get "/web/cash/reports/balance"

        expect(response).to redirect_to(authenticated_root_path)
        expect(flash[:alert]).to be_present
      end
    end
  end

  describe "the range presets" do
    before { sign_in admin }

    def range_inputs
      document = Nokogiri::HTML(response.body)
      [ document.at("#balance-from")["value"], document.at("#balance-to")["value"] ]
    end

    it "defaults to the month" do
      travel_to Date.new(2026, 9, 2) do
        get "/web/cash/reports/balance"
      end

      expect(range_inputs).to eq([ "2026-09-01", "2026-09-30" ])
    end

    it "reads the week as Monday to Sunday" do
      travel_to Date.new(2026, 9, 2) do
        get "/web/cash/reports/balance", params: { period: "week" }
      end

      expect(range_inputs).to eq([ "2026-08-31", "2026-09-06" ])
    end

    it "reads the fortnight as the half of the month the day falls in" do
      travel_to Date.new(2026, 9, 2) do
        get "/web/cash/reports/balance", params: { period: "fortnight" }
      end

      expect(range_inputs).to eq([ "2026-09-01", "2026-09-15" ])
    end

    it "reads the second fortnight from the sixteenth" do
      travel_to Date.new(2026, 9, 20) do
        get "/web/cash/reports/balance", params: { period: "fortnight" }
      end

      expect(range_inputs).to eq([ "2026-09-16", "2026-09-30" ])
    end

    it "takes the dates typed into a custom range" do
      get "/web/cash/reports/balance",
          params: { period: "custom", from: "2026-07-04", to: "2026-08-09" }

      expect(range_inputs).to eq([ "2026-07-04", "2026-08-09" ])
    end

    it "falls back to the month when a custom range is not a pair of dates" do
      travel_to Date.new(2026, 9, 2) do
        get "/web/cash/reports/balance", params: { period: "custom", from: "no-es-fecha" }
      end

      expect(range_inputs).to eq([ "2026-09-01", "2026-09-30" ])
    end

    it "reports on the custom range and not on today" do
      movement(business_date: Date.new(2026, 7, 10), amount: 555_000,
               account: "drawer", channel: "cash")

      get "/web/cash/reports/balance",
          params: { period: "custom", from: "2026-07-04", to: "2026-08-09" }

      expect(response.body).to include("555.000,00")
    end
  end

  describe "the sidebar entry" do
    it "offers the report to the admin" do
      sign_in admin

      get "/web/cash/days/2026-09-03"

      expect(response.body).to include("Balance general")
    end

    it "does not offer it to the cashier" do
      sign_in cashier

      get "/web/cash/days/2026-09-03"

      expect(response.body).not_to include("Balance general")
    end
  end
end
