# frozen_string_literal: true

require "rails_helper"

# Enter submits the product form without a blur, so the amount fields reach
# the server exactly as typed.
RSpec.describe "Product form amounts submitted with Enter", type: :system do
  include Warden::Test::Helpers

  let(:admin)    { create(:user, :admin) }
  let(:product)  { create(:product, name: "Buje", price_unit: 10_000) }

  before do
    driven_by :selenium_chrome_headless, screen_size: [ 1400, 900 ]
    login_as(admin, scope: :user)
    visit edit_web_product_path(product)
  end

  def type_over(label, text)
    field = find_field(label)
    field.send_keys([ :control, "a" ], :backspace)
    field.send_keys(text)
    field
  end

  it "saves a dotted ML price typed without blurring as thousands" do
    type_over("Precio Mercado Libre (ARS)", "15.000").send_keys(:enter)

    expect(page).to have_text("Producto actualizado exitosamente")
    expect(product.reload.price_for("mercadolibre")).to eq(15_000)
  end

  it "saves a plain ML price typed without blurring" do
    type_over("Precio Mercado Libre (ARS)", "15000").send_keys(:enter)

    expect(page).to have_text("Producto actualizado exitosamente")
    expect(product.reload.price_for("mercadolibre")).to eq(15_000)
  end

  it "saves a dotted counter price typed without blurring as thousands" do
    type_over("Precio de Venta (ARS)", "12.500").send_keys(:enter)

    expect(page).to have_text("Producto actualizado exitosamente")
    expect(product.reload.price_unit).to eq(12_500)
  end
end
