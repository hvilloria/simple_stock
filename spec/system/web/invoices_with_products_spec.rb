# frozen_string_literal: true

require "rails_helper"

# The invoice form's Productos card: adding a line, the totals card, the
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

  def totals_row(label)
    find("[data-invoice-lines-target='totals'] [data-totals-row]", text: label)
  end

  context "with the two lines of a discounted invoice" do
    before do
      create(:product, sku: "EXT-CRV2", name: "Extremo Honda CRV 2", current_stock: 0)
      create(:product, sku: "EXT-CRV3", name: "Extremo Honda CRV 3", current_stock: 0)
      add_line("EXT-CRV2", quantity: 6, cost: "8.900,00")
      add_line("EXT-CRV3", quantity: 6, cost: "9.500,00")
    end

    it "totals the paper's discount and IVA live and registers that total" do
      fill_in "discount_percentage", with: "10"

      expect(page).to have_field("iva_percentage", with: "21")
      expect(totals_row("Subtotal")).to have_text("110.400,00")
      expect(totals_row("Descuento 10%")).to have_text("11.040,00")
      expect(totals_row("IVA 21%")).to have_text("20.865,60")
      expect(totals_row("Total a pagar")).to have_text("120.225,60")
      expect(page).to have_text("Comparar con la factura en papel antes de registrar.")
      expect(find("[data-controller='invoice-lines'] tbody tr:first-child [data-final-cost]")).to have_text("9.692,10")
      expect(page).to have_no_field("amount")
      expect(page).to have_no_field("currency_usd", visible: :visible)
      expect(page).to have_text("El stock se suma al registrar y cada producto toma este costo.")
      expect(page).to have_text("+6 Extremo Honda CRV 2 · $ 9.692,10")
      expect(find("[data-invoice-form-target='summaryAmount']")).to have_text("120.225,60")

      click_button "Registrar Factura"

      expect(page).to have_text("Factura registrada exitosamente")
      invoice = Invoice.last
      expect(invoice.amount).to eq(120_225.60)
      expect(invoice.currency).to eq("ARS")
      expect(invoice.discount_percentage).to eq(10)
      expect(invoice.iva_percentage).to eq(21)
    end

    it "comes back with the typed discount and the lines when the discount is out of range" do
      fill_in "discount_percentage", with: "150"

      click_button "Registrar Factura"

      expect(page).to have_text("El descuento debe estar entre 0 y 100")
      expect(page).to have_field("discount_percentage", with: "150")
      expect(page).to have_css("[data-controller='invoice-lines'] tbody tr", count: 2)
      expect(page).to have_text("Extremo Honda CRV 2")
      expect(page).to have_text("Extremo Honda CRV 3")
      expect(page).to have_no_field("currency_usd", visible: :visible)
      expect(page).to have_no_field("amount")
      expect(Invoice.count).to eq(0)
    end
  end

  it "brings back the typed amount and the currency when the last line is removed" do
    choose "currency_usd"
    fill_in "amount", with: "1.000,00"
    add_line("90915", quantity: 1, cost: "100,00")
    expect(page).to have_no_field("amount")
    expect(page).to have_no_field("currency_usd", visible: :visible)

    find("button[title='Quitar']").click

    expect(page).to have_field("amount", with: "1.000,00")
    expect(page).to have_checked_field("currency_usd")
    expect(page).to have_no_css("[data-invoice-lines-target='totals']")
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
    expect(totals_row("Total a pagar")).to have_text("5.445,61")
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

  it "puts a product invoice in pesos even when dollars were chosen" do
    choose "currency_usd"
    fill_in "exchange_rate", with: "1.480,00"
    add_line("90915", quantity: 1, cost: "")

    click_button "Registrar Factura"

    within("[data-invoice-form-target='zeroCostModal']") do
      expect(page).to have_text("Total a pagar: $ 0,00")
      expect(page).to have_no_text("US$")
      click_button "Registrar"
    end

    expect(page).to have_text("Factura registrada exitosamente")
    expect(Invoice.last.currency).to eq("ARS")
  end

  it "does not ask when every cost is above zero" do
    add_line("90915", quantity: 1, cost: "100,00")

    click_button "Registrar Factura"

    expect(page).to have_text("Factura registrada exitosamente")
    expect(page).not_to have_text("Confirmar registro")
  end

  it "hides the products card for a tax invoice" do
    visit new_web_invoice_path
    expect(page).to have_field(placeholder: "Buscar por SKU, nombre o marca...")
    find("label", text: "Impuestos").click
    expect(page).not_to have_field(placeholder: "Buscar por SKU, nombre o marca...")
    find("label", text: "Proveedor", match: :prefer_exact).click
    expect(page).to have_field(placeholder: "Buscar por SKU, nombre o marca...")
  end
end
