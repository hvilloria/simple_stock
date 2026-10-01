# frozen_string_literal: true

require "rails_helper"

# Product fields are typed by staff and rendered by several Stimulus
# controllers that build HTML as strings; each must show them as text.
RSpec.describe "Product fields in client-rendered HTML", type: :system do
  include Warden::Test::Helpers

  let(:admin)     { create(:user, :admin) }
  let!(:location) { create(:stock_location) }
  let(:name)      { %(Llave 1/2' <img src=x onerror="window.injected=true">) }
  let!(:wrench) do
    create(:product, sku: "LLV-0012", name: name, brand: "A&B <b>Bahco</b>", current_stock: 0)
  end

  before do
    driven_by :selenium_chrome_headless, screen_size: [ 1400, 900 ]
    login_as(admin, scope: :user)
  end

  def search_and_pick
    fill_in placeholder: "Buscar por SKU, nombre o marca...", with: "LLV-0012"
    find("[data-product-search-target='results'] [data-action*='selectProduct']", text: "LLV-0012").click
  end

  def expect_text_only
    expect(page).to have_text(name)
    expect(page).to have_no_css("img[src='x']")
    expect(page.evaluate_script("window.injected")).to be_nil
  end

  it "shows search results as text" do
    visit "/web/stock_adjustments/new"
    fill_in placeholder: "Buscar por SKU, nombre o marca...", with: "LLV-0012"

    within("[data-product-search-target='results']") do
      expect(page).to have_text(name)
      expect(page).to have_text("A&B <b>Bahco</b>")
    end
    expect_text_only
  end

  it "picks a product with an apostrophe and shows it as text in the adjustment lines" do
    visit "/web/stock_adjustments/new"
    search_and_pick

    expect(page).to have_css("[data-controller='stock-adjustment-lines'] tbody tr", count: 1)
    expect_text_only
  end

  it "shows a picked product as text on the new sale" do
    visit "/web/orders/new"
    search_and_pick

    expect(page).to have_text("LLV-0012")
    expect_text_only
  end

  it "shows a picked product as text in the invoice lines and summary" do
    visit "/web/invoices/new"
    search_and_pick

    expect(page).to have_css("[data-controller='invoice-lines'] tbody tr", count: 1)
    expect(page).to have_text("Suma stock: 1 unidad en 1 producto")
    expect_text_only
  end

  it "shows a product added to the cart as text" do
    visit "/web/products"
    find("button[title='Agregar al carrito']").click
    find("[data-action='click->cart#togglePanel']").click

    within("[data-cart-target='items']") { expect(page).to have_text(name) }
    expect_text_only
  end
end
