# frozen_string_literal: true

require "rails_helper"

# End-to-end system test for the "pagos a cuenta" (on_account) flow.
#
# Prerequisites:
#   - Google Chrome installed (uses :selenium_chrome_headless driver)
#
# Flow covered (an admin can both deliver and collect):
#   1. Index lists the open operation by contact name.
#   2. Open the detail via the "Ver →" link.
#   3. On the detail, one of two items is pre-delivered ("1 / 2 ítems"); check
#      the pending item and save the delivery → "2 / 2 ítems".
#   4. Go to the collect form, settle the full balance in cash, submit.
#   5. The reloaded order has outstanding_balance 0 and status "confirmed".
#
# Because the order is fully delivered before settling, the Task 15
# soft-confirm dialog must NOT fire.

RSpec.describe "Pagos a cuenta", type: :system do
  include Warden::Test::Helpers

  let(:admin)     { create(:user, role: "admin") }
  let(:product_a) { create(:product, price_unit: 500) }
  let(:product_b) { create(:product, price_unit: 500) }

  let!(:order) do
    o = create(:order, :on_account,
               contact_name: "Juan Pérez",
               contact_phone: "11 5555 1234",
               total_amount: 1000,
               original_total_amount: 1000)
    create(:order_item, :delivered, order: o, product: product_a, quantity: 1, unit_price: 500)
    create(:order_item, order: o, product: product_b, quantity: 1, unit_price: 500)
    o
  end

  before do
    driven_by :selenium_chrome_headless, screen_size: [ 1400, 900 ]
    login_as(admin, scope: :user)
  end

  after { Warden.test_reset! }

  it "lists, opens detail, marks delivery and collects" do
    visit web_payments_on_account_index_path
    expect(page).to have_content("Juan Pérez")

    click_link "Ver →"
    expect(page).to have_content("Operación a cuenta")
    expect(page).to have_content("1 / 2 ítems")

    # Only the undelivered item renders a checkbox (the delivered one shows
    # "✓ entregado"), so there is exactly one "marcar entregado" control.
    check "order_item_ids[]"
    click_button "Guardar entrega"
    expect(page).to have_content("Entrega registrada")
    expect(page).to have_content("2 / 2 ítems")

    click_link "Cobrar →"
    select "Efectivo", from: "payment_method"
    fill_in "amount_to_settle", with: "1000"
    click_button "Registrar cobro"
    expect(page).to have_content("Cobro registrado")

    expect(order.reload.outstanding_balance).to eq(0)
    expect(order.status).to eq("confirmed")
  end
end
