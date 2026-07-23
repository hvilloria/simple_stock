# frozen_string_literal: true

require "rails_helper"

# Minimal system spec for the Stimulus-dependent behavior of the item edit
# form: disabled submit gating and live subtotal/total/balance recompute.
# Everything else (authorization, service failures) is covered by the
# request spec — see spec/requests/web/payments_on_account/items_spec.rb.

RSpec.describe "Pagos a cuenta - cambiar producto de un ítem", type: :system do
  include Warden::Test::Helpers

  let(:vendedor) { create(:user, role: "vendedor") }
  let(:product)  { create(:product, price_unit: 500) }

  let!(:order) do
    o = create(:order, :on_account,
               contact_name: "Juan Pérez",
               contact_phone: "11 5555 1234",
               total_amount: 1000,
               original_total_amount: 1000)
    create(:order_item, order: o, product: product, quantity: 2, unit_price: 500)
    o
  end
  let(:item) { order.order_items.first }

  before do
    driven_by :selenium_chrome_headless, screen_size: [ 1400, 900 ]
    login_as(vendedor, scope: :user)
  end

  after { Warden.test_reset! }

  it "gates the submit button and previews the new subtotal live" do
    visit edit_web_payments_on_account_item_path(order, item)

    expect(page).to have_button("Guardar cambio", disabled: true)

    fill_in "quantity", with: "3"
    expect(page).to have_button("Guardar cambio", disabled: false)
    expect(page).to have_content("$ 1.000,00 → $ 1.500,00")

    fill_in "quantity", with: "2"
    expect(page).to have_button("Guardar cambio", disabled: true)
  end
end
