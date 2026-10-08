# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Channel prices on a new sale", type: :system do
  include Warden::Test::Helpers

  let(:vendedor) { create(:user, :vendedor) }
  let!(:location) { create(:stock_location) }
  let!(:buje) { create(:product, sku: "BUJE-1", name: "Buje parrilla", price_unit: 10_000, current_stock: 5) }

  before do
    driven_by :selenium_chrome_headless, screen_size: [ 1400, 900 ]
    login_as(vendedor, scope: :user)
    buje.channel_prices.create!(channel: "mercadolibre", price: 15_000)
  end

  it "re-prefills every line with the channel price and back" do
    visit new_web_order_path(product_id: buje.id)
    expect(page).to have_field(with: "10.000,00")

    price = find("input[data-controller='currency-input']")
    price.send_keys([ :control, "a" ], :backspace, "12000")
    price.send_keys(:tab)
    expect(page).to have_field(with: "12.000,00")

    select "🛒 Mercado Libre", from: "Canal de Venta"
    expect(page).to have_content("Se actualizaron los precios al canal Mercado Libre.")
    expect(page).to have_content("En Mercado Libre el precio que pongas actualiza el precio de Mercado Libre del producto, no el de mostrador.")
    expect(page).to have_field(with: "15.000,00")

    select "🏪 Mostrador", from: "Canal de Venta"
    expect(page).to have_field(with: "10.000,00")
  end

  it "hides the notice when the lines are gone" do
    visit new_web_order_path(product_id: buje.id)
    select "🛒 Mercado Libre", from: "Canal de Venta"
    expect(page).to have_content("Se actualizaron los precios al canal Mercado Libre.")

    find("button[title='Eliminar']").click
    select "💬 WhatsApp", from: "Canal de Venta"
    expect(page).to have_no_content("Se actualizaron los precios")
  end

  it "prefills a searched product with the channel price" do
    visit new_web_order_path
    select "🛒 Mercado Libre", from: "Canal de Venta"
    fill_in placeholder: "Buscar por SKU, nombre o marca...", with: "BUJE-1"
    result = find("[data-product-search-target='results'] [data-action*='selectProduct']", text: "BUJE-1")
    expect(result).to have_content("15.000")
    result.click

    expect(page).to have_field(with: "15.000,00")
  end

  it "keeps the 'se lo lleva ahora' choice when the lines are redrawn" do
    create(:product, sku: "ROT-1", name: "Rotula", price_unit: 5_000, current_stock: 5)
    visit new_web_order_path(product_id: buje.id)
    find("label[for='order_type_on_account']").click
    check "se lo lleva ahora"

    select "🛒 Mercado Libre", from: "Canal de Venta"
    expect(page).to have_content("Se actualizaron los precios al canal Mercado Libre.")
    expect(page).to have_checked_field("se lo lleva ahora")

    fill_in placeholder: "Buscar por SKU, nombre o marca...", with: "ROT-1"
    find("[data-product-search-target='results'] [data-action*='selectProduct']", text: "ROT-1").click
    expect(page).to have_content("Rotula")
    expect(all("input[name='delivered_product_ids[]']").map(&:checked?)).to eq([ true, false ])
  end
end
