# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Ajuste de stock", type: :system do
  include Warden::Test::Helpers

  let(:admin)     { create(:user, :admin, name: "Hosward") }
  let!(:location) { create(:stock_location) }
  let!(:filter)   { create(:product, sku: "90915-YZZD2", name: "Filtro de aceite Toyota", current_stock: 0) }

  before do
    create(:stock_movement, product: filter, stock_location: location, quantity: 12, movement_type: "purchase")
    filter.recalculate_current_stock!
    driven_by :selenium_chrome_headless, screen_size: [ 1400, 900 ]
    login_as(admin, scope: :user)
    visit "/web/stock_adjustments/new"
  end

  def add_product(query)
    fill_in placeholder: "Buscar por SKU, nombre o marca...", with: query
    find("[data-product-search-target='results'] [data-action*='selectProduct']", text: query, match: :first).click
  end

  it "shows the difference as the admin types and saves the count" do
    add_product("90915")
    expect(page).to have_button("Guardar ajuste", disabled: true)

    within("[data-controller='stock-adjustment-lines'] tbody tr") do
      expect(page).to have_text("12")
      find("input[type='number']").fill_in(with: "9")
      expect(page).to have_text("−3")
    end
    fill_in "note", with: "Conteo de fin de mes"

    click_button "Guardar ajuste"

    expect(page).to have_text("Ajuste guardado: 1 producto actualizado")
    expect(filter.reload.current_stock).to eq(9)
  end

  it "does not add a product twice" do
    add_product("90915")
    add_product("90915")

    expect(page).to have_css("[data-controller='stock-adjustment-lines'] tbody tr", count: 1)
  end

  it "keeps the button off while a row has no count" do
    air = create(:product, sku: "17801-0H050", name: "Filtro de aire Toyota", current_stock: 0)
    create(:stock_movement, product: air, stock_location: location, quantity: 5, movement_type: "purchase")
    air.recalculate_current_stock!

    add_product("90915")
    add_product("17801")
    find("[data-line-index='0'] input[type='number']").fill_in(with: "9")
    fill_in "note", with: "Conteo"

    expect(page).to have_button("Guardar ajuste", disabled: true)

    find("[data-line-index='1'] input[type='number']").fill_in(with: "5")

    expect(page).to have_button("Guardar ajuste", disabled: false)

    find("[data-line-index='0'] input[type='number']").fill_in(with: "12")
    within("[data-line-index='0']") { expect(page).to have_text("sin cambio") }
    expect(page).to have_button("Guardar ajuste", disabled: true)
  end

  it "keeps the button off for a count above the limit" do
    add_product("90915")
    find("[data-line-index='0'] input[type='number']").fill_in(with: "1000001")
    fill_in "note", with: "Conteo"

    within("[data-line-index='0']") { expect(page).to have_css("[data-difference]", text: "—") }
    expect(page).to have_button("Guardar ajuste", disabled: true)
  end

  it "does not submit when Enter is pressed in the search box" do
    add_product("90915")
    find("[data-line-index='0'] input[type='number']").fill_in(with: "9")
    fill_in "note", with: "Conteo"
    expect(page).to have_button("Guardar ajuste", disabled: false)

    find_field(placeholder: "Buscar por SKU, nombre o marca...").send_keys("qqq", :enter)

    expect(page).to have_text("No se encontraron productos")
    within("[data-line-index='0']") { expect(page).to have_field(type: "number", with: "9") }
    expect(filter.reload.current_stock).to eq(12)
  end
end
