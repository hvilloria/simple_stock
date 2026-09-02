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

  describe "the fixed-expense breakdown" do
    before { sign_in admin }

    def breakdown
      Nokogiri::HTML(response.body).at("#fixed-expense-breakdown")
    end

    def cells_of(row) = row.css("th, td").map { |cell| cell.text.strip }

    it "expands inside the report instead of sending the owner to another screen" do
      get "/web/cash/reports/balance"

      expect(breakdown).to be_present
      expect(breakdown.text).to include("Gastos fijos por subcategoría")
    end

    it "reads at the reporting group, the same columns the report's rows use" do
      get "/web/cash/reports/balance"

      headers = breakdown.css("thead th").map { |cell| cell.text.strip }
      expect(headers).to eq([ "Subcategoría", "Efectivo", "Banco", "Mercado Pago", "USD" ])
    end

    it "lists the six subcategories even when a month has none of them" do
      get "/web/cash/reports/balance"

      labels = breakdown.css("tbody tr").map { |row| cells_of(row).first }
      expect(labels)
        .to eq([ "Alquiler", "Salarios", "Cargas sociales", "Impuestos", "Servicios", "Gastos de local" ])
    end

    it "puts each subcategory against the arca it was paid from" do
      travel_to Date.new(2026, 9, 2) do
        movement(category: "fixed_expense", subcategory: "rent", channel: nil,
                 account: "main_cash", amount: -400_000)
        movement(category: "fixed_expense", subcategory: "taxes", channel: nil,
                 account: "bank", amount: -96_300)

        get "/web/cash/reports/balance"
      end

      rent = breakdown.css("tbody tr").find { |row| cells_of(row).first == "Alquiler" }
      taxes = breakdown.css("tbody tr").find { |row| cells_of(row).first == "Impuestos" }

      expect(cells_of(rent)).to eq([ "Alquiler", "-400.000,00", "0,00", "0,00", "0,00" ])
      expect(cells_of(taxes)).to eq([ "Impuestos", "0,00", "-96.300,00", "0,00", "0,00" ])
    end

    it "closes with the totals the fixed-expenses column of each row shows" do
      travel_to Date.new(2026, 9, 2) do
        movement(category: "fixed_expense", subcategory: "rent", channel: nil,
                 account: "main_cash", amount: -400_000)
        movement(category: "fixed_expense", subcategory: "utilities", channel: nil,
                 account: "drawer", amount: -37_400)
        movement(category: "fixed_expense", subcategory: "taxes", channel: nil,
                 account: "bank", amount: -96_300)

        get "/web/cash/reports/balance"
      end

      totals = cells_of(breakdown.at("tfoot tr"))
      expect(totals).to eq([ "Total", "-437.400,00", "-96.300,00", "0,00", "0,00" ])

      balance_row = Nokogiri::HTML(response.body).css("#balance-rows tr").first
      expect(balance_row.css("td")[4].text.strip).to eq("-437.400,00")
    end
  end

  describe "GET /web/cash/reports/history" do
    def rows
      Nokogiri::HTML(response.body).css("#movement-rows tr")
    end

    def cells_of(row) = row.css("td").map { |cell| cell.text.strip }

    context "as the admin" do
      before { sign_in admin }

      it "lists the movements of the range, showing the fine arca" do
        travel_to Date.new(2026, 9, 2) do
          movement(account: "main_cash", category: "suppliers", channel: nil,
                   amount: -153_951, description: "Cromosol")

          get "/web/cash/reports/history"
        end

        expect(response).to have_http_status(:ok)
        expect(rows.size).to eq(1)
        expect(cells_of(rows.first)).to include("Caja grande", "Proveedores", "Cromosol")
      end

      it "leaves out what falls outside the range" do
        travel_to Date.new(2026, 9, 2) do
          movement(business_date: Date.new(2026, 10, 5), amount: 777_777,
                   account: "drawer", channel: "cash")

          get "/web/cash/reports/history"
        end

        expect(rows).to be_empty
      end

      # Filter coarse, read fine: the four groups the balance report reads at,
      # never the six arcas, or the two screens would disagree.
      it "offers the four reporting groups in the arca filter, not the six arcas" do
        get "/web/cash/reports/history"

        options = Nokogiri::HTML(response.body).css("select[name=group] option").map { |o| o.text.strip }
        expect(options).to eq([ "Todas las arcas", "Efectivo", "Banco", "Mercado Pago", "USD" ])
      end

      it "matches every fine arca of the group the filter names" do
        travel_to Date.new(2026, 9, 2) do
          movement(account: "drawer", amount: 10_000, description: "En la caja del día")
          movement(account: "main_cash", category: "suppliers", channel: nil,
                   amount: -20_000, description: "En la caja grande")
          movement(:card_sale, description: "En el banco")

          get "/web/cash/reports/history", params: { group: "efectivo" }
        end

        expect(rows.size).to eq(2)
        expect(response.body).to include("En la caja del día", "En la caja grande")
        expect(response.body).not_to include("En el banco")
      end

      it "narrows by category" do
        travel_to Date.new(2026, 9, 2) do
          movement(:store_expense, description: "Gasto de local")
          movement(account: "drawer", amount: 10_000, description: "Una venta")

          get "/web/cash/reports/history", params: { category: "fixed_expense" }
        end

        expect(rows.size).to eq(1)
        expect(response.body).to include("Gasto de local")
        expect(response.body).not_to include("Una venta")
      end

      it "narrows by description search" do
        travel_to Date.new(2026, 9, 2) do
          movement(:supplier_payment, description: "Cromosol")
          movement(:supplier_payment, description: "Otro proveedor")

          get "/web/cash/reports/history", params: { search: "cromo" }
        end

        expect(rows.size).to eq(1)
        expect(response.body).to include("Cromosol")
      end

      it "narrows by the custom period" do
        movement(business_date: Date.new(2026, 7, 10), amount: 555_000,
                 account: "drawer", channel: "cash", description: "De julio")
        movement(business_date: Date.new(2026, 9, 10), amount: 111_000,
                 account: "drawer", channel: "cash", description: "De septiembre")

        get "/web/cash/reports/history",
            params: { period: "custom", from: "2026-07-04", to: "2026-08-09" }

        expect(rows.size).to eq(1)
        expect(response.body).to include("De julio")
        expect(response.body).not_to include("De septiembre")
      end

      it "combines the filters instead of letting one override another" do
        travel_to Date.new(2026, 9, 2) do
          movement(account: "main_cash", category: "suppliers", channel: nil,
                   amount: -50_000, description: "Cromosol agosto")
          movement(:card_sale, description: "Cromosol agosto")
          movement(account: "main_cash", category: "suppliers", channel: nil,
                   amount: -50_000, description: "Otro proveedor")

          get "/web/cash/reports/history",
              params: { group: "efectivo", category: "suppliers", search: "cromosol" }
        end

        expect(rows.size).to eq(1)
      end

      it "paginates instead of pouring the whole history onto one page" do
        travel_to Date.new(2026, 9, 2) do
          25.times { |i| movement(account: "drawer", amount: 1_000 + i) }

          get "/web/cash/reports/history"
        end

        expect(rows.size).to eq(20)
        expect(response.body).to include("Siguiente")

        travel_to Date.new(2026, 9, 2) do
          get "/web/cash/reports/history", params: { page: 2 }
        end

        expect(rows.size).to eq(5)
      end

      # Editing happens on the open day and nowhere else, whoever is looking.
      it "offers no edit or delete affordance, not even to the admin" do
        travel_to Date.new(2026, 9, 2) do
          movement(:store_expense)

          get "/web/cash/reports/history"
        end

        table = Nokogiri::HTML(response.body).at("#movement-rows")
        expect(table.text).not_to include("Editar")
        expect(table.text).not_to include("Eliminar")
        expect(table.css("a, form, button")).to be_empty
      end

      it "shows an empty state when no row matches" do
        get "/web/cash/reports/history", params: { search: "nada de nada" }

        expect(response.body).to include("No hay movimientos con esos filtros")
      end
    end

    context "as the cashier" do
      before { sign_in cashier }

      it "turns her away even when she types the URL" do
        get "/web/cash/reports/history"

        expect(response).to redirect_to(authenticated_root_path)
        expect(flash[:alert]).to be_present
      end
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

    it "offers the history to the admin" do
      sign_in admin

      get "/web/cash/days/2026-09-03"

      expect(response.body).to include("Historial de movimientos")
    end

    it "does not offer the history to the cashier" do
      sign_in cashier

      get "/web/cash/days/2026-09-03"

      expect(response.body).not_to include("Historial de movimientos")
    end
  end
end
