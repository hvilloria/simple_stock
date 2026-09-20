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

      def cards
        Nokogiri::HTML(response.body).css("#holdings [data-group]")
      end

      def figure_of(group)
        Nokogiri::HTML(response.body).at("#holdings [data-group=#{group}] [data-amount]").text.strip
      end

      it "shows the four holdings, the dollars as dollars, and no flow column" do
        get "/web/cash/reports/balance"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Balance general")
        expect(cards.map { |card| card.at("[data-label]").text.strip })
          .to eq([ "Efectivo", "Banco", "Mercado Pago", "Dólares" ])
        expect(figure_of("usd")).to start_with("US$")
        expect(response.body).not_to include("Saldo inicial", "Socio", "Entre arcas", "Diferencias")
        expect(response.body).not_to include("Gastos fijos por subcategoría")
        expect(Nokogiri::HTML(response.body).css("table")).to be_empty
      end

      it "says the movements that lost their columns are still in the figures" do
        get "/web/cash/reports/balance"

        expect(response.body).to include("movimientos entre arcas")
        expect(response.body).to include(web_cash_movement_history_path)
      end

      it "reads the holdings at today by default" do
        travel_to Date.new(2026, 9, 19) do
          movement(:opening_balance, account: "main_cash", business_date: Date.new(2026, 8, 20),
                                     amount: 1_000_000)
          movement(account: "drawer", channel: "cash", amount: 324_700)
          movement(:store_expense, amount: -13_000, business_date: Date.new(2026, 9, 19))
          movement(account: "usd", channel: "usd", amount: 500)

          get "/web/cash/reports/balance"
        end

        expect(Nokogiri::HTML(response.body).at("input[name=on]")["value"]).to eq("2026-09-19")
        expect(figure_of("efectivo")).to eq("$ 1.311.700,00")
        expect(figure_of("usd")).to eq("US$ 500,00")
      end

      it "reads the holdings at the date asked for, leaving out what came after it" do
        travel_to Date.new(2026, 9, 19) do
          movement(account: "drawer", channel: "cash", amount: 324_700)
          movement(account: "drawer", channel: "cash", amount: 777_777, business_date: Date.new(2026, 9, 4))

          get "/web/cash/reports/balance", params: { on: "2026-09-03" }
        end

        expect(Nokogiri::HTML(response.body).at("input[name=on]")["value"]).to eq("2026-09-03")
        expect(figure_of("efectivo")).to eq("$ 324.700,00")
      end

      it "reads a future date as today, since nothing is dated after it" do
        travel_to Date.new(2026, 9, 19) do
          get "/web/cash/reports/balance", params: { on: "2026-12-31" }
        end

        expect(Nokogiri::HTML(response.body).at("input[name=on]")["value"]).to eq("2026-09-19")
      end

      it "reads a date that does not parse as today" do
        travel_to Date.new(2026, 9, 19) do
          get "/web/cash/reports/balance", params: { on: "no-es-fecha" }
        end

        expect(Nokogiri::HTML(response.body).at("input[name=on]")["value"]).to eq("2026-09-19")
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

  describe "GET /web/cash/reports/history" do
    def rows
      Nokogiri::HTML(response.body).css("#movement-rows tr")
    end

    def cells_of(row) = row.css("td").map { |cell| cell.text.strip }

    context "as the admin" do
      before { sign_in admin }

      it "lists the movements of the range, showing the fine arca" do
        travel_to Date.new(2026, 9, 30) do
          movement(account: "main_cash", category: "suppliers", channel: nil,
                   amount: -153_951, description: "Cromosol")

          get "/web/cash/reports/history"
        end

        expect(response).to have_http_status(:ok)
        expect(rows.size).to eq(1)
        expect(cells_of(rows.first)).to include("Caja grande", "Proveedores", "Cromosol")
      end

      it "leaves out what falls outside the range" do
        travel_to Date.new(2026, 10, 6) do
          movement(business_date: Date.new(2026, 10, 5), amount: 777_777,
                   account: "drawer", channel: "cash")

          get "/web/cash/reports/history", params: { period: "custom", from: "2026-09-01", to: "2026-09-30" }
        end

        expect(rows).to be_empty
      end

      # Filtered to one arca you only see one leg, and a large row with no
      # counterpart reads as money that evaporated.
      it "states the counterpart of a transfer leg" do
        travel_to Date.new(2026, 9, 30) do
          ::Cash::RecordTransfer.call(from: "drawer", to: "bank", amount: 80_000,
                                      business_date: Date.new(2026, 9, 3), user: admin)

          get "/web/cash/reports/history", params: { group: "efectivo" }
        end

        expect(rows.size).to eq(1)
        expect(cells_of(rows.first).join(" ")).to include("hacia Banco")
      end

      it "does not label an ordinary row with a counterpart" do
        travel_to Date.new(2026, 9, 30) do
          movement(account: "drawer", amount: 10_000, description: "Venta del día")

          get "/web/cash/reports/history"
        end

        expect(cells_of(rows.first).join(" ")).not_to match(/hacia|desde/)
      end

      # Filter coarse, read fine: the four groups the balance report reads at,
      # never the six arcas, or the two screens would disagree.
      it "offers the four reporting groups in the arca filter, not the six arcas" do
        get "/web/cash/reports/history"

        options = Nokogiri::HTML(response.body).css("select[name=group] option").map { |o| o.text.strip }
        expect(options).to eq([ "Todas las arcas", "Efectivo", "Banco", "Mercado Pago", "USD" ])
      end

      it "matches every fine arca of the group the filter names" do
        travel_to Date.new(2026, 9, 30) do
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

      # The compensations of a period are otherwise unfindable: they have no
      # arca, and their category is the same "Venta" every sale carries.
      it "offers every channel in the channel filter" do
        get "/web/cash/reports/history"

        options = Nokogiri::HTML(response.body).css("select[name=channel] option").map { |o| o.text.strip }
        expect(options).to eq([ "Todos los canales", "Efectivo", "Tarjeta", "QR", "Transferencia",
                                "Mercado Pago", "USD", "Compensación" ])
      end

      it "narrows by channel" do
        travel_to Date.new(2026, 9, 30) do
          movement(:compensation_sale, description: "Compensada")
          movement(:card_sale, description: "Con tarjeta")
          movement(account: "drawer", amount: 10_000, description: "En efectivo")

          get "/web/cash/reports/history", params: { channel: "compensation" }
        end

        expect(rows.size).to eq(1)
        expect(response.body).to include("Compensada")
        expect(response.body).not_to include("Con tarjeta")
      end

      it "combines the channel filter with the period" do
        movement(:compensation_sale, business_date: Date.new(2026, 7, 10), description: "De julio")
        movement(:compensation_sale, business_date: Date.new(2026, 9, 10), description: "De septiembre")

        get "/web/cash/reports/history",
            params: { channel: "compensation", period: "custom", from: "2026-07-04", to: "2026-08-09" }

        expect(rows.size).to eq(1)
        expect(response.body).to include("De julio")
        expect(response.body).not_to include("De septiembre")
      end

      it "names the supplier whose debt a compensation cancels" do
        travel_to Date.new(2026, 9, 30) do
          supplier = create(:supplier, name: "Cromosol")
          movement(:compensation_sale, supplier: supplier, description: "Compensada")

          get "/web/cash/reports/history"
        end

        expect(cells_of(rows.first)).to include("Cromosol")
      end

      it "leaves the supplier blank on a row that is not a compensation" do
        travel_to Date.new(2026, 9, 30) do
          movement(account: "drawer", amount: 10_000, description: "Una venta")

          get "/web/cash/reports/history"
        end

        headers = Nokogiri::HTML(response.body).css("thead th").map { |cell| cell.text.strip }
        expect(cells_of(rows.first)[headers.index("Proveedor")]).to eq("—")
      end

      it "narrows by category" do
        travel_to Date.new(2026, 9, 30) do
          movement(:store_expense, description: "Gasto de local")
          movement(account: "drawer", amount: 10_000, description: "Una venta")

          get "/web/cash/reports/history", params: { category: "fixed_expense" }
        end

        expect(rows.size).to eq(1)
        expect(response.body).to include("Gasto de local")
        expect(response.body).not_to include("Una venta")
      end

      it "narrows by description search" do
        travel_to Date.new(2026, 9, 30) do
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
        travel_to Date.new(2026, 9, 30) do
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
        travel_to Date.new(2026, 9, 30) do
          25.times { |i| movement(account: "drawer", amount: 1_000 + i) }

          get "/web/cash/reports/history"
        end

        expect(rows.size).to eq(20)
        expect(response.body).to include("Siguiente")

        travel_to Date.new(2026, 9, 30) do
          get "/web/cash/reports/history", params: { page: 2 }
        end

        expect(rows.size).to eq(5)
      end

      # Editing happens on the open day and nowhere else, whoever is looking.
      it "offers no edit or delete affordance, not even to the admin" do
        travel_to Date.new(2026, 9, 30) do
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

      # The point of the foot is the filter, not the page: a filter cut into
      # three pages still adds up to one figure.
      describe "the total of the filter" do
        def total(name)
          Nokogiri::HTML(response.body).at("#movement-totals [data-total=#{name}]")&.text&.strip
        end

        it "adds up the whole filter and not just the page on screen" do
          travel_to Date.new(2026, 9, 30) do
            30.times { movement(amount: 10_000) }
            movement(:store_expense, amount: -13_000)

            get "/web/cash/reports/history"
          end

          expect(rows.size).to eq(20)
          expect(total("inflow")).to eq("300.000,00")
          expect(total("outflow")).to eq("13.000,00")
        end

        it "adds up what the filters left" do
          travel_to Date.new(2026, 9, 30) do
            movement(amount: 10_000)
            movement(:store_expense, amount: -13_000)

            get "/web/cash/reports/history", params: { category: "fixed_expense" }
          end

          expect(total("inflow")).to eq("0,00")
          expect(total("outflow")).to eq("13.000,00")
        end

        it "adds the dollars up on their own line, never into the pesos" do
          travel_to Date.new(2026, 9, 30) do
            movement(amount: 10_000)
            movement(account: "usd", channel: "usd", amount: 500)

            get "/web/cash/reports/history"
          end

          expect(total("inflow")).to eq("10.000,00")
          expect(total("usd_inflow")).to eq("US$ 500,00")
        end

        it "leaves the dollar line out when the filter has none" do
          travel_to Date.new(2026, 9, 30) do
            movement(amount: 10_000)

            get "/web/cash/reports/history"
          end

          expect(total("usd_inflow")).to be_nil
        end
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

  describe "the sidebar entries" do
    context "as the admin" do
      before { sign_in admin }

      it "offers the whole module" do
        get "/web/cash/days/2026-09-03"

        expect(response.body).to include("Balance general")
        expect(response.body).to include("Historial de movimientos")
        expect(response.body).to include(web_cash_days_path)
      end

      it "marks Balance general as a scale, not a trend" do
        get "/web/cash/days/2026-09-03"

        link = Nokogiri::HTML(response.body).css("a[href='#{web_cash_balance_report_path}']")
                       .find { |a| a.text.include?("Balance general") }
        expect(link.text).to include("⚖️")
        expect(link.text).not_to include("📈")
      end
    end

    # She is sent to the dashboard: no cash screen renders for her at all, so
    # the sidebar is read from a screen she can still reach.
    context "as the cashier" do
      before { sign_in cashier }

      it "offers her none of the three cash screens" do
        get authenticated_root_path

        expect(response.body).not_to include("Balance general")
        expect(response.body).not_to include("Historial de movimientos")
        expect(response.body).not_to include(web_cash_days_path)
      end
    end
  end
end
