# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Selling a combo from the sale form", type: :system do
  include Warden::Test::Helpers

  let(:vendedor) { create(:user, :vendedor) }
  let!(:location) { create(:stock_location) }
  let!(:left) { create(:product, sku: "12345-123-12345", name: "Amortiguador delantero izq.", price_unit: 70_000) }
  let!(:right) { create(:product, sku: "12345-456-12345", name: "Amortiguador delantero der.", price_unit: 70_000) }
  let!(:combo) do
    create(:product, :combo, sku: "CB-0001", name: "Par amortiguadores delanteros", price_unit: 100_000,
                             components: [ [ left, 1 ], [ right, 1 ] ])
  end

  def stock!(product, quantity)
    create(:stock_movement, product: product, stock_location: location, quantity: quantity)
    product.recalculate_current_stock!
  end

  def pick_combo
    fill_in placeholder: "Buscar por SKU, nombre o marca...", with: "456"
    find("[data-product-search-target='results'] [data-action*='selectProduct']", text: "CB-0001").click
    expect(page).to have_text("↳ 1 × 12345-123-12345 · stock 5")
  end

  before do
    stock!(left, 5)
    stock!(right, 3)
    driven_by :selenium_chrome_headless, screen_size: [ 1400, 900 ]
    login_as(vendedor, scope: :user)
  end

  it "sells the combo as one line and moves each component's stock" do
    visit new_web_order_path
    fill_in "paper_number", with: "0045"
    pick_combo
    expect(page).to have_text("↳ 1 × 12345-456-12345 · stock 3")
    expect(page).to have_no_field("se lo lleva ahora", visible: :all)

    price = find("input[data-controller='currency-input']")
    price.send_keys([ :control, "a" ], :backspace, "95000")
    price.send_keys(:tab)
    expect(page).to have_field(with: "95.000,00")

    click_button "Crear nota de pedido"

    expect(page).to have_text("CB-0001")
    expect(page).to have_text("↳ 1 × 12345-123-12345 · Amortiguador delantero izq.")
    expect(page).to have_text("↳ 1 × 12345-456-12345 · Amortiguador delantero der.")
    expect(left.reload.current_stock).to eq(4)
    expect(right.reload.current_stock).to eq(2)
    expect(combo.reload.price_unit).to eq(95_000)
  end

  it "blocks the sale while a combo line is on an on-account order" do
    visit new_web_order_path
    fill_in "paper_number", with: "0045"
    pick_combo
    expect(page).to have_button("Crear nota de pedido", disabled: false)

    find("label[for='order_type_on_account']").click

    expect(page).to have_text("Los combos todavía no se pueden vender en pago a cuenta. Quitar el combo o cambiar el tipo de venta.")
    expect(page).to have_button("Crear nota de pedido", disabled: true)

    fill_in placeholder: "Buscar por SKU, nombre o marca...", with: "456"
    within("[data-product-search-target='results']") do
      expect(page).to have_text("12345-456-12345")
      expect(page).to have_no_text("CB-0001")
    end
  end
end
