# frozen_string_literal: true

require "rails_helper"

# The day screen's entry row: the mode control, the fields each answer shows
# or disables, and the translation of the operator's answers into the
# parameters the server takes. That translation is JavaScript, so this is the
# only layer that sees it; rendering, refusals and authorization live in the
# request specs under spec/requests/web/cash.

RSpec.describe "Caja - fila de carga del día", type: :system do
  include Warden::Test::Helpers

  mode_labels = { "in" => "Entrada", "out" => "Salida", "move" => "Transferencia" }

  # How each way of paying is answered on screen, and the arca it must store.
  payments = [
    { method: "Efectivo",     pile: "Caja del día", account: "drawer" },
    { method: "Efectivo",     pile: "Caja grande",  account: "main_cash" },
    { method: "Efectivo",     pile: "Remanente",    account: "change_fund" },
    { method: "Banco",        pile: nil,            account: "bank" },
    { method: "Mercado Pago", pile: nil,            account: "mercado_pago" },
    { method: "USD",          pile: nil,            account: "usd" }
  ]

  sales = [
    { channel: "Efectivo",      stores: { channel: "cash",         account: "drawer" } },
    { channel: "Tarjeta",       stores: { channel: "card",         account: "bank" } },
    { channel: "QR",            stores: { channel: "qr",           account: "bank" } },
    { channel: "Transferencia", stores: { channel: "transfer",     account: "bank" } },
    { channel: "Mercado Pago",  stores: { channel: "mercado_pago", account: "mercado_pago" } },
    { channel: "USD",           stores: { channel: "usd",          account: "usd" } },
    { channel: "Compensación",  supplier: "Cromosol",
      stores: { channel: "compensation", account: nil, supplier: "Cromosol" } }
  ]

  fixed_expenses = {
    "Alquiler"        => "rent",
    "Salarios"        => "salaries",
    "Cargas sociales" => "social_charges",
    "Impuestos"       => "taxes",
    "Servicios"       => "utilities",
    "Gastos de local" => "store_expenses"
  }

  # The parameter contract, one row per answer the screen can give.
  contract = [
    *sales.map do |sale|
      { mode: "in", kind: "Venta", channel: sale[:channel], supplier: sale[:supplier],
        stores: { category: "sale", sign: :+ }.merge(sale[:stores]) }
    end,
    *payments.map do |pay|
      { mode: "in", kind: "Aporte de socio", method: pay[:method], pile: pay[:pile],
        stores: { category: "partner", account: pay[:account], sign: :+ } }
    end,
    *payments.map do |pay|
      { mode: "out", kind: "Proveedor", method: pay[:method], pile: pay[:pile],
        stores: { category: "suppliers", account: pay[:account], sign: :- } }
    end,
    *fixed_expenses.each_with_index.map do |(label, key), index|
      pay = payments[index % payments.size]
      { mode: "out", kind: label, method: pay[:method], pile: pay[:pile],
        stores: { category: "fixed_expense", subcategory: key, account: pay[:account], sign: :- } }
    end,
    *payments.map do |pay|
      { mode: "out", kind: "Retiro de socio", method: pay[:method], pile: pay[:pile],
        stores: { category: "partner", account: pay[:account], sign: :- } }
    end
  ]

  let(:admin)         { create(:user, :admin) }
  let(:business_date) { Date.new(2026, 8, 3) }
  let(:day_path)      { "/web/cash/days/#{business_date}" }

  let!(:supplier) { create(:supplier, name: "Cromosol") }

  before do
    driven_by :selenium_chrome_headless, screen_size: [ 1400, 900 ]
    login_as(admin, scope: :user)
  end

  after { Warden.test_reset! }

  def mode_button(mode)
    "#day-entry-form button[data-mode='#{mode}']"
  end

  def group(mode)
    "#day-entry-form fieldset[data-mode='#{mode}']"
  end

  def expect_mode(mode, focused: true)
    selector = "#{mode_button(mode)}[aria-pressed='true']"
    expect(page).to have_css(focused ? "#{selector}:focus" : selector)
    expect(page).to have_css(group(mode), visible: :visible)
    (%w[in out move] - [ mode ]).each do |other|
      expect(page).to have_css("#{group(other)}[disabled]", visible: :hidden)
    end
  end

  def load_entry(mode:, amount: "1500", description: nil, kind: nil, channel: nil, supplier: nil,
                 method: nil, pile: nil)
    find(mode_button(mode)).click
    within(group(mode)) do
      fill_in "Descripción", with: description if description
      select kind, from: "Qué es" if kind
      select channel, from: "Cómo pagó" if channel
      select supplier, from: "Proveedor" if supplier
      select method, from: mode == "in" ? "Cómo entró" : "Cómo se pagó" if method
      select pile, from: "De qué caja" if pile
      fill_in "Monto", with: amount
      click_button "Guardar"
    end
  end

  def load_transfer(from:, to:, amount:, description: nil)
    find(mode_button("move")).click
    within(group("move")) do
      fill_in "day-entry-move-amount", with: amount
      select from, from: "day-entry-move-from"
      select to, from: "day-entry-move-to"
      fill_in "day-entry-move-description", with: description if description
      click_button "Guardar"
    end
  end

  # The figure lives in the footer of the sales panel, next to its own label.
  def amount_to_wrap
    find("#sales-by-channel")
      .find(:xpath, ".//span[normalize-space()='Monto a fajar']/following-sibling::span")
      .text
  end

  describe "the parameter contract" do
    contract.each do |row|
      answers = [ mode_labels[row[:mode]], row[:kind], row[:channel], row[:supplier], row[:method], row[:pile] ]

      it "stores what #{answers.compact.join(' · ')} means" do
        visit day_path
        load_entry(**row.except(:stores))

        expect(page).to have_css("#day-entries tr", count: 1)

        expected = { subcategory: nil, channel: nil, supplier: nil }.merge(row[:stores])
        movement = CashMovement.sole
        expect(
          category: movement.category,
          subcategory: movement.subcategory,
          channel: movement.channel,
          account: movement.account,
          sign: movement.amount.positive? ? :+ : :-,
          supplier: movement.supplier&.name
        ).to eq(expected)
        expect(movement.amount.abs).to eq(1500)
      end
    end

    it "stores a Transferencia as two legs, from one arca to the other" do
      visit day_path
      load_transfer(from: "Mercado Pago", to: "Banco", amount: "50000", description: "Retiro de Mercado Pago")

      expect(page).to have_css("#day-entries tr", count: 1)

      legs = CashMovement.order(:amount).map { |leg| [ leg.category, leg.account, leg.amount, leg.description ] }
      expect(legs).to eq([
        [ "internal_transfer", "mercado_pago", -50_000, "Retiro de Mercado Pago" ],
        [ "internal_transfer", "bank", 50_000, "Retiro de Mercado Pago" ]
      ])
    end
  end

  describe "the mode control" do
    it "opens on Salida with the focus on the control" do
      visit day_path

      expect_mode("out")
    end

    it "switches mode with E, S, T and the arrows while it has focus, and not from a text field" do
      visit day_path
      expect_mode("out")

      page.send_keys("e")
      expect_mode("in")

      page.send_keys("t")
      expect_mode("move")

      page.send_keys(:left)
      expect_mode("out")

      page.send_keys(:right)
      expect_mode("move")

      page.send_keys("s")
      expect_mode("out")

      find_field("day-entry-out-description").click
      page.send_keys("est")
      expect(page).to have_field("day-entry-out-description", with: "est")
      expect_mode("out", focused: false)
    end
  end

  describe "saving a row" do
    it "appends it with its glyph and signed amount, and hands back an empty form on the same mode" do
      visit day_path

      load_entry(mode: "out", description: "Cromosol", kind: "Proveedor", method: "Banco", amount: "153951")

      row = find("#day-entries tr", text: "Cromosol")
      expect(row).to have_content("↑")
      expect(row).to have_content("−153.951,00")
      expect(row).to have_content("Banco")

      expect_mode("out")
      within(group("out")) do
        expect(page).to have_field("Descripción", with: "")
        expect(page).to have_field("Monto", with: "")
      end

      load_entry(mode: "in", description: "Venta mostrador", kind: "Venta", channel: "Efectivo")

      row = find("#day-entries tr", text: "Venta mostrador")
      expect(row).to have_content("↓")
      expect(row).to have_content("1.500,00")
      expect(row).to have_no_content("−")
      expect(page).to have_css("#day-entries tr", count: 2)

      expect_mode("in")
      within(group("in")) do
        expect(page).to have_field("Descripción", with: "")
        expect(page).to have_field("Monto", with: "")
      end
    end

    it "formats the amount in Argentine format when the field loses focus" do
      visit day_path

      within(group("out")) do
        fill_in "Monto", with: "324700"
        find_field("Descripción").click

        expect(page).to have_field("Monto", with: "324.700,00")
      end
    end

    it "refuses an amount that is not a number and writes no row" do
      visit day_path

      load_entry(mode: "out", description: "Monto ilegible", amount: "abc")

      expect(page).to have_content("El monto no es un número.")
      expect(page).to have_no_css("#day-entries tr")
      expect(CashMovement.count).to eq(0)
    end
  end

  # R-6: what the drawer should hold is defined by the arca a row names.
  describe "the amount to wrap" do
    let!(:cash_sale) { create(:cash_movement, business_date: business_date, amount: 299_700) }

    it "moves only for money that touches the drawer" do
      visit day_path
      expect(amount_to_wrap).to eq("299.700,00")

      load_entry(mode: "out", description: "Bolsas", kind: "Gastos de local", method: "Efectivo",
                 pile: "Caja del día", amount: "25000")
      expect(page).to have_css("#day-entries tr", count: 2)
      expect(amount_to_wrap).to eq("274.700,00")

      load_entry(mode: "out", description: "Luz", kind: "Servicios", method: "Efectivo",
                 pile: "Caja grande", amount: "10000")
      expect(page).to have_css("#day-entries tr", count: 3)
      expect(amount_to_wrap).to eq("274.700,00")

      load_entry(mode: "out", description: "Cromosol", kind: "Proveedor", method: "Banco", amount: "10000")
      expect(page).to have_css("#day-entries tr", count: 4)
      expect(amount_to_wrap).to eq("274.700,00")

      load_entry(mode: "in", description: "Venta mostrador", kind: "Venta", channel: "Efectivo")
      expect(page).to have_css("#day-entries tr", count: 5)
      expect(amount_to_wrap).to eq("276.200,00")
    end

    it "does not move for a compensation, which reaches no caja" do
      visit day_path

      load_entry(mode: "in", description: "Compensación Cromosol", kind: "Venta", channel: "Compensación",
                 supplier: "Cromosol", amount: "661188")

      row = find("#day-entries tr", text: "Compensación Cromosol")
      expect(row).to have_content("Compensación · Cromosol")
      expect(row).to have_content("661.188,00")
      expect(page).to have_css("#sales-by-channel", text: "661.188,00")
      expect(amount_to_wrap).to eq("299.700,00")
    end

    it "moves for a transfer out of the drawer, and not for one between two other arcas" do
      visit day_path

      load_transfer(from: "Mercado Pago", to: "Banco", amount: "50000")
      row = find("#day-entries tr", text: "Mercado Pago → Banco")
      expect(row).to have_content("50.000,00")
      expect(page).to have_css("#day-entries tr", count: 2)
      expect(amount_to_wrap).to eq("299.700,00")
      expect_mode("move")

      load_transfer(from: "Caja del día", to: "Banco", amount: "80000", description: "Depósito del día")
      expect(page).to have_css("#day-entries tr", count: 3)
      expect(find("#day-entries tr", text: "Depósito del día")).to have_content("Caja del día → Banco")
      expect(amount_to_wrap).to eq("219.700,00")
    end
  end

  describe "the fields each answer shows" do
    it "asks for the pile only when the money is cash, and starts it on Caja del día" do
      visit day_path

      within(group("out")) do
        expect(page).to have_select("De qué caja", selected: "Caja del día")

        select "Caja grande", from: "De qué caja"
        select "Banco", from: "Cómo se pagó"
        expect(page).to have_no_select("De qué caja")
        expect(page).to have_select("day-entry-out-pile", visible: :hidden, disabled: true)

        select "Efectivo", from: "Cómo se pagó"
        expect(page).to have_select("De qué caja", selected: "Caja del día", disabled: false)
      end
    end

    it "asks how a sale was paid, and how a contribution came in" do
      visit day_path
      find(mode_button("in")).click

      within(group("in")) do
        expect(page).to have_select("Cómo pagó", disabled: false)
        expect(page).to have_select("day-entry-in-method", visible: :hidden, disabled: true)
        expect(page).to have_select("day-entry-in-pile", visible: :hidden, disabled: true)

        select "Aporte de socio", from: "Qué es"
        expect(page).to have_select("day-entry-channel", visible: :hidden, disabled: true)
        expect(page).to have_select("Cómo entró", selected: "Efectivo", disabled: false)
        expect(page).to have_select("De qué caja", selected: "Caja del día", disabled: false)

        select "Venta", from: "Qué es"
        expect(page).to have_select("Cómo pagó", disabled: false)
        expect(page).to have_select("day-entry-in-method", visible: :hidden, disabled: true)
      end
    end

    it "shows the supplier only on a compensation sale and disables it everywhere else" do
      visit day_path
      find(mode_button("in")).click

      within(group("in")) do
        expect(page).to have_select("day-entry-supplier", visible: :hidden, disabled: true)

        select "Compensación", from: "Cómo pagó"
        expect(page).to have_select("Proveedor", disabled: false)

        select "Efectivo", from: "Cómo pagó"
        expect(page).to have_select("day-entry-supplier", visible: :hidden, disabled: true)

        select "Compensación", from: "Cómo pagó"
        select "Aporte de socio", from: "Qué es"
        expect(page).to have_select("day-entry-supplier", visible: :hidden, disabled: true)
      end
    end

    it "saves an ordinary sale with no supplier when the channel moves away from compensation" do
      visit day_path
      find(mode_button("in")).click

      within(group("in")) do
        fill_in "Descripción", with: "Venta mostrador"
        select "Compensación", from: "Cómo pagó"
        select "Cromosol", from: "Proveedor"
        select "Efectivo", from: "Cómo pagó"
        fill_in "Monto", with: "1500"
        click_button "Guardar"
      end

      expect(page).to have_css("#day-entries tr", count: 1)
      movement = CashMovement.sole
      expect(movement.supplier).to be_nil
      expect(movement.channel).to eq("cash")
    end
  end

  describe "editing a row" do
    let!(:expense) do
      create(:cash_movement, :store_expense, business_date: business_date, account: "main_cash")
    end

    it "prefills the form with the mode locked, and saves the correction in place" do
      visit day_path
      within("#entry_#{expense.id}") { click_link "Editar" }

      within("#entry_#{expense.id}") do
        expect(page).to have_css("button[data-mode='out'][aria-pressed='true'][disabled]")
        expect(page).to have_css("button[data-mode='in'][disabled]")
        expect(page).to have_field("Descripción", with: "Mundo de la Bolsa — 100 bolsas")
        expect(page).to have_select("Qué es", selected: "Gastos de local")
        expect(page).to have_select("Cómo se pagó", selected: "Efectivo")
        expect(page).to have_select("De qué caja", selected: "Caja grande")
        expect(page).to have_field("Monto", with: "13.000,00")

        # fill_in selects the old value before focusing, and the focus unformats
        # it, so the new digits would be appended; type over it instead.
        find_field("Monto").send_keys([ :control, "a" ], :backspace, "20000")
        select "Remanente", from: "De qué caja"
        click_button "Guardar"
      end

      row = find("#entry_#{expense.id}", text: "−20.000,00")
      expect(row).to have_content("Efectivo · Remanente")
      expect(row).to have_link("Editar")
      expect(expense.reload.amount).to eq(-20_000)
      expect(expense.account).to eq("change_fund")
    end

    it "restores the row on Cancelar without a request" do
      visit day_path
      within("#entry_#{expense.id}") { click_link "Editar" }
      within("#entry_#{expense.id}") { fill_in "Descripción", with: "Otra cosa" }

      # A request would render a new body; the marker only survives without one.
      page.execute_script("document.body.dataset.probe = 'kept'")
      within("#entry_#{expense.id}") { click_link "Cancelar" }

      row = find("#entry_#{expense.id}", text: "Mundo de la Bolsa — 100 bolsas")
      expect(row).to have_content("−13.000,00")
      expect(row).to have_link("Editar")
      expect(row).to have_no_field("Descripción")
      expect(page.evaluate_script("document.body.dataset.probe")).to eq("kept")
      expect(expense.reload.description).to eq("Mundo de la Bolsa — 100 bolsas")
    end
  end

  describe "a closed day" do
    let!(:expense) { create(:cash_movement, :store_expense, business_date: business_date) }

    before { create(:daily_closing, business_date: business_date) }

    it "shows the list with no form and no edit affordances" do
      visit day_path

      expect(page).to have_css("#day-entries tr", text: "Mundo de la Bolsa — 100 bolsas")
      expect(page).to have_no_css("#day-entry-form")
      expect(page).to have_no_button("Guardar")
      expect(page).to have_no_link("Editar")
      expect(page).to have_no_button("Eliminar")
    end
  end
end
