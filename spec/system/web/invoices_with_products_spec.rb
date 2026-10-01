# frozen_string_literal: true

require "rails_helper"

# The invoice form's Productos card: adding a line, the frozen amount, the
# summary, and the zero-cost confirmation. The server side is covered by the
# request and service specs.
RSpec.describe "Facturas con productos", type: :system do
  include Warden::Test::Helpers

  let(:admin)     { create(:user, role: "admin") }
  let!(:location) { create(:stock_location) }
  let!(:supplier) { create(:supplier, name: "Cromosol") }
  let!(:filter)   { create(:product, sku: "90915-YZZD2", name: "Filtro de aceite Toyota", current_stock: 0) }

  before do
    driven_by :selenium_chrome_headless, screen_size: [ 1400, 900 ]
    login_as(admin, scope: :user)
    visit "/web/invoices/new"
    select "Cromosol", from: "supplier_id"
    fill_in "invoice_number", with: "FAC-0001234"
    choose "currency_ars"
  end

  def add_line(query, quantity:, cost:)
    fill_in placeholder: "Buscar por SKU, nombre o marca...", with: query
    find("[data-product-search-target='results'] [data-action*='selectProduct']", text: query, match: :first).click
    within("[data-controller='invoice-lines'] tbody tr:last-child") do
      find("input[type='number']").fill_in(with: quantity)
      cost_input = find("[data-cost]")
      cost_input.fill_in(with: cost)
      cost_input.send_keys(:tab)
    end
  end

  it "freezes the amount to the sum, says what will be stocked, and registers the lines" do
    add_line("90915", quantity: 10, cost: "4.500,00")

    amount = find("#amount")
    expect(amount).to be_readonly
    expect(amount.value).to eq("45.000,00")
    expect(page).to have_text("Suma stock: 10 unidades en 1 producto")
    expect(page).to have_text("1 producto · 10 unidades")

    click_button "Registrar Factura"

    expect(page).to have_text("Factura registrada exitosamente")
    expect(filter.reload.current_stock).to eq(10)
    expect(Invoice.last.amount).to eq(45_000)
  end

  it "unfreezes the amount when the last line is removed" do
    fill_in "amount", with: "1.000,00"
    add_line("90915", quantity: 1, cost: "100,00")
    expect(find("#amount").value).to eq("100,00")

    find("button[title='Quitar']").click

    amount = find("#amount")
    expect(amount).not_to be_readonly
    expect(amount.value).to eq("1.000,00")
    expect(page).to have_text("Sin productos: no mueve stock")
  end

  it "asks for a second look at a free line, and only then" do
    add_line("90915", quantity: 2, cost: "")
    expect(find("[data-cost]").value).to eq("0,00")

    click_button "Registrar Factura"

    within("[data-invoice-form-target='zeroCostModal']") do
      expect(page).to have_text("1 línea con costo 0")
      expect(page).to have_text("Filtro de aceite Toyota")
      click_button "Volver a revisar"
    end
    expect(Invoice.count).to eq(0)
    expect(page).to have_css("[data-invoice-form-target='zeroCostModal'].hidden", visible: :all)

    click_button "Registrar Factura"
    within("[data-invoice-form-target='zeroCostModal']") { click_button "Registrar" }

    expect(page).to have_text("Factura registrada exitosamente")
    expect(Invoice.last.amount).to eq(0)
    expect(filter.reload.current_stock).to eq(2)
  end

  # The hidden input carries the Argentine format the server and the card both
  # read, so a cost with cents survives a refusal untouched.
  it "keeps a cost with cents when the server refuses the invoice" do
    add_line("90915", quantity: 1, cost: "4.500,50")
    fill_in "due_date", with: Date.current - 1

    click_button "Registrar Factura"

    expect(page).to have_text("Due date cannot be before purchase date")
    expect(find("[data-cost]").value).to eq("4.500,50")
    expect(find("#amount").value).to eq("4.500,50")
    expect(Invoice.count).to eq(0)
  end

  # The re-rendered amount is Argentine-formatted, so the retry cleans it once
  # and not twice: a second pass would submit 1250050.
  it "keeps an amount-only invoice's amount when the first attempt is refused" do
    fill_in "amount", with: "12.500,50"
    fill_in "purchase_date", with: Date.current.to_s
    fill_in "due_date", with: (Date.current - 1).to_s

    click_button "Registrar Factura"

    expect(page).to have_text("Due date cannot be before purchase date")
    expect(find("#amount").value).to eq("12.500,50")

    fill_in "due_date", with: (Date.current + 30).to_s
    click_button "Registrar Factura"

    expect(page).to have_text("Factura registrada exitosamente")
    expect(Invoice.last.amount).to eq(12_500.5)
  end

  it "names the free line's cost in the invoice's currency" do
    choose "currency_usd"
    fill_in "exchange_rate", with: "1.480,00"
    add_line("90915", quantity: 1, cost: "")

    click_button "Registrar Factura"

    within("[data-invoice-form-target='zeroCostModal']") do
      expect(page).to have_text("US$ 0,00")
      expect(page).to have_text("Monto de la factura: US$")
      click_button "Volver a revisar"
    end
    expect(Invoice.count).to eq(0)
  end

  it "does not ask when every cost is above zero" do
    add_line("90915", quantity: 1, cost: "100,00")

    click_button "Registrar Factura"

    expect(page).to have_text("Factura registrada exitosamente")
    expect(page).not_to have_text("Confirmar registro")
  end
end
