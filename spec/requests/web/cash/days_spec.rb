# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Web::Cash::Days", type: :request do
  let(:admin) { create(:user, role: "admin") }
  let(:date)  { Date.new(2026, 8, 3) }

  describe "GET /web/cash/days" do
    it "sends the admin to today" do
      sign_in admin

      get "/web/cash/days"

      expect(response).to redirect_to("/web/cash/days/#{Date.current}")
    end
  end

  describe "GET /web/cash/days/:business_date" do
    before { sign_in admin }

    it "renders the day's movements" do
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

  describe "the day's list" do
    let(:supplier) { create(:supplier, name: "Pinturerías Rex") }

    before { sign_in admin }

    def list
      Nokogiri::HTML(response.body).at("#day-entries")
    end

    def row(movement)
      list.at("#entry_#{movement.id}")
    end

    def row_text(movement)
      row(movement).text.squish
    end

    def glyph(movement)
      row(movement).at("td").text.squish
    end

    def drawer_dot?(movement)
      row(movement).at("[title='Cuenta en el cajón']").present?
    end

    def automatic_sale
      payment = create(:payment, amount: 20_000)
      order = create(:order, :invoice_a, customer: payment.customer, paper_number: "3340", total_amount: 20_000)
      create(:payment_allocation, payment: payment, order: order, amount: 20_000)
      create(:cash_movement, business_date: date, source_payment: payment, amount: 20_000)
    end

    def transfer(from:, to:, amount: "400000")
      ::Cash::RecordTransfer.call(from: from, to: to, amount: amount, business_date: date, user: admin).record
    end

    context "with one movement of every kind" do
      let!(:cash_sale) { create(:cash_movement, business_date: date, description: "Mostrador", amount: 1_000) }
      let!(:card_sale) { create(:cash_movement, :card_sale, business_date: date, description: "Posnet") }
      let!(:supplier_from_bank) { create(:cash_movement, :supplier_payment, business_date: date, description: "Cromosol") }
      let!(:till_expense) { create(:cash_movement, :store_expense, business_date: date, description: "Bolsas") }
      let!(:expense_from_main_cash) do
        create(:cash_movement, :store_expense, business_date: date, subcategory: "salaries", account: "main_cash",
                                               amount: -400_000, description: "Julio")
      end
      let!(:withdrawal) do
        create(:cash_movement, business_date: date, category: "partner", channel: nil, account: "change_fund",
                               amount: -500_000, description: "Juan retira")
      end
      let!(:contribution) do
        create(:cash_movement, business_date: date, category: "partner", channel: nil, account: "bank",
                               amount: 200_000, description: "Juan pone")
      end
      let!(:compensation) do
        create(:cash_movement, :compensation_sale, business_date: date, supplier: supplier, description: "Canje")
      end
      let!(:collected) { automatic_sale }
      let!(:legs) { transfer(from: "mercado_pago", to: "bank") }

      before { get "/web/cash/days/2026-08-03" }

      it "renders one row per entry, the transfer folded into one" do
        expect(list.css("tr").size).to eq(10)
        expect(list.at("#entry_#{legs.last.id}")).to be_nil
      end

      it "starts each row with the direction it moved in" do
        expect([ cash_sale, card_sale, contribution, compensation, collected ].map { |m| glyph(m) }.uniq).to eq([ "↓" ])
        expect([ supplier_from_bank, till_expense, expense_from_main_cash, withdrawal ].map { |m| glyph(m) }.uniq)
          .to eq([ "↑" ])
        expect(glyph(legs.first)).to eq("⇄")
      end

      it "signs an outflow and leaves an inflow and a transfer plain" do
        expect(row_text(till_expense)).to include("−13.000,00")
        expect(row_text(supplier_from_bank)).to include("−153.951,00")
        expect(row_text(cash_sale)).to include("1.000,00")
        expect(row_text(cash_sale)).not_to include("−")
        expect(row_text(legs.first)).to include("400.000,00")
        expect(row_text(legs.first)).not_to include("−")
      end

      it "names a sale's channel, and the supplier of a compensation" do
        expect(row_text(cash_sale)).to include("Efectivo")
        expect(row_text(card_sale)).to include("Tarjeta")
        expect(row_text(compensation)).to include("Compensación · Pinturerías Rex")
      end

      it "names the method of anything else, with the cash pile only when it is not the till" do
        expect(row_text(till_expense)).to include("Efectivo")
        expect(row_text(till_expense)).not_to include("Caja del día")
        expect(row_text(expense_from_main_cash)).to include("Efectivo · Caja grande")
        expect(row_text(withdrawal)).to include("Efectivo · Remanente")
        expect(row_text(supplier_from_bank)).to include("Banco")
        expect(row_text(contribution)).to include("Banco")
      end

      it "writes a transfer as where the money went" do
        expect(row_text(legs.first)).to include("Mercado Pago → Banco")
      end

      it "marks exactly the rows whose money touched the till" do
        dotted = [ cash_sale, till_expense ]
        undotted = [ card_sale, supplier_from_bank, expense_from_main_cash, withdrawal, contribution,
                     compensation, legs.first ]

        dotted.each { |movement| expect(drawer_dot?(movement)).to be(true), "#{movement.description} has no dot" }
        undotted.each { |movement| expect(drawer_dot?(movement)).to be(false), "#{movement.description} has a dot" }
      end

      it "shows each note a collection settled with its invoice type, and marks the row automatic" do
        expect(row_text(collected)).to include("3340 · A", "Automático")
        expect(row_text(cash_sale)).not_to include("Automático")
      end

      it "says only what was written: no category, no filler, no first person" do
        text = list.text.squish
        labels = CashMovement::CATEGORY_LABELS.values + CashMovement::SUBCATEGORY_LABELS.values

        labels.each { |label| expect(text).not_to include(label) }
        expect(text).not_to include("Cobro de nota")
        expect(text).not_to include("Moví")
        expect(text).to include("Mostrador", "Cromosol", "Bolsas", "Julio", "Juan retira", "Juan pone", "Canje")
      end
    end

    it "marks a transfer that left or reached the till" do
      legs = transfer(from: "drawer", to: "main_cash")

      get "/web/cash/days/2026-08-03"

      expect(drawer_dot?(legs.first)).to be(true)
      expect(row_text(legs.first)).to include("Caja del día → Caja grande")
    end

    it "shows a transfer's description only when one was written" do
      written = ::Cash::RecordTransfer.call(from: "main_cash", to: "bank", amount: "1000", business_date: date,
                                            user: admin, description: "Depósito").record

      get "/web/cash/days/2026-08-03"

      expect(row_text(written.first)).to include("Depósito")
    end

    it "never uses the ids of the two zones it replaced" do
      create(:cash_movement, business_date: date)

      get "/web/cash/days/2026-08-03"

      %w[drawer-rows drawer-live-row arca-rows arca-live-row].each do |old_id|
        expect(response.body).not_to include(old_id)
      end
      expect(response.body).to include('id="day-entries"', 'id="day-entry-form"')
    end
  end

  describe "the entry form" do
    before do
      sign_in admin
      get "/web/cash/days/2026-08-03"
    end

    def form
      Nokogiri::HTML(response.body).at("#day-entry-form")
    end

    def group(mode)
      form.at("[data-cash-entry-target='group'][data-mode='#{mode}']")
    end

    def hidden_value(name)
      form.at("input[type='hidden'][name='#{name}']")["value"].to_s
    end

    it "opens on the question: entrada, salida or transferencia, on Salida" do
      buttons = form.css("[data-cash-entry-target='mode']")

      expect(buttons.map { |b| b["data-mode"] }).to eq(%w[in out move])
      expect(buttons.map { |b| b.text.squish }).to eq([ "↓ Entrada", "↑ Salida", "⇄ Entre arcas" ])
      expect(buttons.select { |b| b["aria-pressed"] == "true" }.map { |b| b["data-mode"] }).to eq([ "out" ])
      expect(form["data-cash-entry-mode-value"]).to eq("out")
    end

    it "shows the Salida group and renders the other two hidden and disabled" do
      expect(group("out").key?("hidden")).to be(false)
      expect(group("out").key?("disabled")).to be(false)

      %w[in move].each do |mode|
        expect(group(mode).key?("hidden")).to be(true)
        expect(group(mode).key?("disabled")).to be(true)
      end
    end

    it "labels each field above it" do
      labels = form.css("label > span:first-child").map { |span| span.text.squish }

      expect(labels).to include("Descripción", "Cómo pagó", "Proveedor", "Qué es", "Cómo se pagó", "Cómo entró",
                                "De qué caja", "Monto", "De", "A")
    end

    it "carries Salida's defaults in the hidden parameters: a supplier, paid in cash from the till" do
      expect(hidden_value("category")).to eq("suppliers")
      expect(hidden_value("subcategory")).to eq("")
      expect(hidden_value("direction")).to eq("")
      expect(hidden_value("account")).to eq("drawer")
    end

    it "lists every kind of outflow as one flat list, the partner's included for the admin" do
      kinds = group("out").css("[data-cash-entry-target='kind'] option").map { |o| [ o.text, o["value"] ] }

      expect(kinds).to eq([
        [ "Proveedor", "suppliers" ],
        [ "Alquiler", "fixed_expense:rent" ],
        [ "Sueldos", "fixed_expense:salaries" ],
        [ "Cargas sociales", "fixed_expense:social_charges" ],
        [ "Impuestos", "fixed_expense:taxes" ],
        [ "Servicios", "fixed_expense:utilities" ],
        [ "Gastos de local", "fixed_expense:store_expenses" ],
        [ "Retiro de socio", "partner" ]
      ])
    end

    it "offers the admin a contribution as the one entrada that is not a sale" do
      kinds = group("in").css("[data-cash-entry-target='kind'] option").map { |o| [ o.text, o["value"] ] }

      expect(kinds).to eq([ [ "Venta", "sale" ], [ "Aporte de socio", "partner" ] ])
    end

    it "asks how an outflow was paid, and from which pile only for cash" do
      methods = group("out").css("[data-cash-entry-target='method'] option").map { |o| [ o.text, o["value"] ] }
      piles = group("out").css("[data-cash-entry-target='pile'] option").map { |o| [ o.text, o["value"] ] }

      expect(methods).to eq([ [ "Efectivo", "cash" ], [ "Banco", "bank" ], [ "Mercado Pago", "mercado_pago" ], [ "USD", "usd" ] ])
      expect(piles).to eq([ [ "Caja del día", "drawer" ], [ "Caja grande", "main_cash" ], [ "Remanente", "change_fund" ] ])
      expect(group("out").at("[data-cash-entry-target='method']")["name"]).to be_nil
      expect(group("out").at("[data-cash-entry-target='pile']")["name"]).to be_nil
    end

    it "offers compensation as a way to pay, and keeps its supplier hidden and disabled until it is chosen" do
      channels = group("in").css("[data-cash-entry-target='channel'] option").map(&:text)
      supplier = group("in").at("[data-cash-entry-target='supplier']")

      expect(channels).to include("Compensación — no entra plata")
      expect(supplier.key?("disabled")).to be(true)
      expect(supplier.ancestors("label").first.key?("hidden")).to be(true)
    end

    it "moves money with no preview, from Caja grande to Banco by default" do
      transfer_form = form.at("form[action='/web/cash/transfers']")

      expect(transfer_form.at("select[name='from'] option[selected]")["value"]).to eq("main_cash")
      expect(transfer_form.at("select[name='to'] option[selected]")["value"]).to eq("bank")
    end
  end

  describe "POST /web/cash/movements" do
    before { sign_in admin }

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
    it "turns the cashier away: the module is admin-only for now" do
      sign_in create(:user, role: "caja")

      get "/web/cash/days/2026-08-03"

      expect(response).to redirect_to(authenticated_root_path)
      expect(flash[:alert]).to be_present
    end

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

  describe "a day whose cash expenses exceeded its cash sales" do
    before do
      sign_in admin
      create(:cash_movement, business_date: date, channel: "cash", account: "drawer", amount: 50_000)
      create(:cash_movement, :store_expense, business_date: date, amount: -350_000)

      get "/web/cash/days/2026-08-03"
    end

    it "never shows the amount to wrap as a negative number" do
      expect(response.body).not_to include("-300.000")
    end

    it "says the bundles covered the day instead" do
      expect(response.body).to include("El cajón no alcanzó")
      expect(response.body).to include("300.000,00")
    end
  end

  describe "the direction arrows" do
    before do
      sign_in create(:user, role: "admin")
      create(:cash_movement, business_date: date, channel: "cash", account: "drawer", description: "Venta mostrador")
      create(:cash_movement, :store_expense, business_date: date, description: "Bolsas")

      get "/web/cash/days/2026-08-03"
    end

    let(:page_html) { Nokogiri::HTML(response.body) }
    let(:glyph_of) { ->(text) { page_html.at("#day-entries tr:contains('#{text}') td") } }

    it "draws an inflow in green and an outflow in red" do
      expect(glyph_of.("Venta mostrador")["class"]).to include("text-emerald-600")
      expect(glyph_of.("Venta mostrador")["class"]).not_to include("text-red-600")
      expect(glyph_of.("Bolsas")["class"]).to include("text-red-600")
      expect(glyph_of.("Bolsas")["class"]).not_to include("text-emerald-600")
    end
  end

  describe "a closed day" do
    before do
      sign_in admin
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

    it "offers no entry form" do
      expect(response.body).not_to include("day-entry-form")
      expect(response.body).not_to include('data-controller="cash-entry"')
    end

    it "still renders the list" do
      expect(response.body).to include('id="day-entries"')
    end

    it "offers no way to correct a row" do
      expect(response.body).not_to include("Editar")
      expect(response.body).not_to include("Eliminar")
    end
  end

  describe "a row born from a collection" do
    before { sign_in admin }

    it "offers no way to correct it" do
      create(:cash_movement, :from_collection, business_date: date, description: "Cobro a cuenta")

      get "/web/cash/days/2026-08-03"

      expect(response.body).to include("Cobro a cuenta")
      expect(response.body).not_to include("Editar")
      expect(response.body).not_to include("Eliminar")
    end

    it "offers them on a row the admin typed the same day" do
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

    it "shows the paper number of the note the collection settled" do
      customer = create(:customer, :with_credit)
      payment = create(:payment, customer: customer, amount: 100)
      order = create(:order, customer: customer, paper_number: "0042", total_amount: 100)
      create(:payment_allocation, payment: payment, order: order, amount: 100)
      create(:cash_movement, business_date: date, source_payment: payment, description: "Cobro a cuenta")

      get "/web/cash/days/2026-08-03"

      expect(response.body).to include(">Nota<")
      expect(response.body).to include("0042")
    end
  end

  describe "a transfer" do
    before { sign_in admin }

    let!(:legs) do
      ::Cash::RecordTransfer.call(from: "drawer", to: "main_cash", amount: "1000", business_date: date,
                                  user: admin, description: "Cierre de caja del día").record
    end

    it "reads as one movement between arcas" do
      get "/web/cash/days/2026-08-03"

      expect(response.body).to include("⇄", "Caja del día → Caja grande")
    end

    it "leaves an ordinary row without the arrow" do
      movement = create(:cash_movement, business_date: date, description: "Mostrador")

      get "/web/cash/days/2026-08-03"

      expect(Nokogiri::HTML(response.body).at("#entry_#{movement.id}").text).not_to include("⇄", "→")
    end

    it "offers no way to correct it" do
      get "/web/cash/days/2026-08-03"

      expect(response.body).not_to include("Editar")
      expect(response.body).not_to include("Eliminar")
    end
  end

  describe "a day that has not come yet" do
    before do
      sign_in admin

      travel_to Date.new(2026, 8, 2) do
        get "/web/cash/days/2026-08-03"
      end
    end

    it "still renders the list" do
      expect(response.body).to include('id="day-entries"')
    end

    it "offers no entry form" do
      expect(response.body).not_to include("day-entry-form")
      expect(response.body).not_to include('data-controller="cash-entry"')
    end

    it "offers no way to close it" do
      expect(response.body).not_to include("Cerrar el día")
    end
  end

  describe "a past day that was left open" do
    before do
      sign_in admin

      travel_to Date.new(2026, 8, 4) do
        get "/web/cash/days/2026-08-03"
      end
    end

    it "offers the entry form" do
      expect(response.body).to include('id="day-entry-form"')
      expect(response.body).to include('data-controller="cash-entry"')
    end

    it "offers the way to close it" do
      expect(response.body).to include("Cerrar el día")
    end
  end

  describe "an open day" do
    before do
      sign_in admin
      create(:cash_movement, business_date: date, description: "Venta mostrador")

      get "/web/cash/days/2026-08-03"
    end

    it "offers the entry form" do
      expect(response.body).to include('id="day-entry-form"')
      expect(response.body).to include('data-controller="cash-entry"')
    end

    it "offers the correction affordances" do
      expect(response.body).to include("Editar")
      expect(response.body).to include("Eliminar")
    end
  end
end
