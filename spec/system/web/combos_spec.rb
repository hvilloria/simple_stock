# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Combo form", type: :system do
  include Warden::Test::Helpers

  let(:admin) { create(:user, :admin) }

  before do
    create(:product, sku: "AMO-IZQ", name: "Amortiguador izquierdo", price_unit: 70_000)
    create(:product, sku: "AMO-DER", name: "Amortiguador derecho", price_unit: 70_000)
    create(:product, sku: "RET-01", name: "Reten de horquilla", price_unit: 20_000)

    driven_by :selenium_chrome_headless, screen_size: [ 1400, 900 ]
    login_as(admin, scope: :user)
  end

  def add_part(query, name)
    find("input[placeholder='Buscar por SKU, nombre o marca...']").send_keys(query)
    find("[data-product-search-target='results']").find("p", text: name).click
  end

  def type_over(field, text)
    field.send_keys([ :control, "a" ], :backspace)
    field.send_keys(text)
  end

  it "prefills the price from the parts until it is typed by hand" do
    visit web_products_path
    click_link "Nuevo Combo"
    expect(page).to have_text("El código se asigna al guardar")

    fill_in "Nombre", with: "Par amortiguadores"
    add_part("izquierdo", "Amortiguador izquierdo")
    add_part("derecho", "Amortiguador derecho")

    expect(page).to have_css("[data-combo-form-target='sum']", text: "$140.000")
    price = find_field("Precio de Venta (ARS)")
    expect(price.value).to eq("140.000,00")

    type_over(price, "100.000")
    add_part("Reten", "Reten de horquilla")

    expect(page).to have_css("[data-combo-form-target='sum']", text: "$160.000")
    expect(price.value).to eq("100.000,00")
    expect(page).to have_text("$60.000 menos que comprar las piezas por separado")

    click_button "Crear Combo"

    expect(page).to have_text("Combo creado")
    combo = Product.combos.last
    expect(page).to have_current_path(web_product_path(combo))
    expect(combo.price_unit).to eq(100_000)
    expect(combo.combo_components.count).to eq(3)
  end

  it "lists a combo next to its parts in Todos and counts it on the Combos tab" do
    left = create(:product, sku: "12345-123-12345", name: "Amortiguador izq. CRF250")
    right = create(:product, sku: "12345-456-12345", name: "Amortiguador der. CRF250")
    combo = create(:product, :combo, name: "Par amortiguadores CRF250", components: [ [ left, 1 ], [ right, 1 ] ])

    visit web_products_path
    fill_in placeholder: "Buscar por código OEM, nombre o marca...", with: "456"

    within("turbo-frame#products_list") do
      expect(page).to have_css("tr", text: "Amortiguador der. CRF250")
      expect(page).to have_css("tr", text: "Par amortiguadores CRF250")
      expect(page).to have_no_css("tr", text: "Amortiguador izq. CRF250")
      expect(find("tr", text: "Par amortiguadores CRF250"))
        .to have_text("Incluye: 12345-123-12345 · 12345-456-12345")
      find("tr", text: "Par amortiguadores CRF250").click_button("+")
    end

    click_button "Carrito"
    within("[data-cart-target='items']") do
      expect(page).to have_text(combo.sku)
      expect(page).to have_no_text("Stock:")
    end
    find("body").send_keys(:escape)

    click_link "Combos (1)"
    expect(page).to have_css("tr", text: "Par amortiguadores CRF250")
    expect(page).to have_no_css("tr", text: "Amortiguador der. CRF250")
  end
end
