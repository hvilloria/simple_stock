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
#
# A second example covers splitting a partial collection across two payment
# methods: the amounts only become editable once a second tender row exists.

RSpec.describe "Pagos a cuenta", type: :system do
  include Warden::Test::Helpers

  let(:admin)     { create(:user, role: "admin") }
  let!(:location) { create(:stock_location) }
  let(:product_a) { create(:product, price_unit: 500, current_stock: 0) }
  let(:product_b) { create(:product, price_unit: 500, current_stock: 0) }

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
    create(:stock_movement, product: product_b, stock_location: location, quantity: 4, movement_type: "purchase")
    product_b.recalculate_current_stock!
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
    select "Efectivo", from: "tenders[0][payment_method]"
    find("[data-on-account-payment-target='tenderAmount']").set("1000", clear: :backspace)
    click_button "Registrar cobro"
    expect(page).to have_content("Cobro registrado")

    expect(order.reload.outstanding_balance).to eq(0)
    expect(order.status).to eq("confirmed")
  end

  it "splits a partial collection across two payment methods" do
    visit new_web_payments_on_account_payment_path(order)

    click_button "+ Agregar método"

    rows = all("[data-on-account-payment-target='tenderRow']")
    # currency-input unformats on focus, which drops Capybara's select-all;
    # backspacing clears the field regardless.
    within(rows[0]) { select "Efectivo" }
    rows[0].find("input").set("300", clear: :backspace)
    within(rows[1]) { select "Banco Transferencia" }
    rows[1].find("input").set("200", clear: :backspace)

    click_button "Registrar cobro"
    expect(page).to have_content("Cobro registrado")

    order.reload
    expect(order.outstanding_balance).to eq(500)
    expect(order.payments.map(&:payment_method)).to contain_exactly("cash", "bank_transfer")
  end

  it "shows how far the cash lowers the debt with the cash discount, and offers to settle it all" do
    big = create(:order, :on_account, customer: Customer.mostrador, user: create(:user, :vendedor),
                 total_amount: 1_704_400, original_total_amount: 1_704_400)
    create(:order_item, order: big, product: create(:product), quantity: 1, unit_price: 1_704_400)

    visit new_web_payments_on_account_payment_path(big)
    select "Efectivo", from: "tenders[0][payment_method]"
    find("[data-on-account-payment-target='tenderAmount']").set("800000", clear: :backspace)
    select "10%", from: "discount_percent"

    expect(page).to have_css("[data-on-account-payment-target='settledLine']", text: "888.889")
    expect(page).to have_css("[data-on-account-payment-target='balanceAfter']", text: "815.511")

    click_button "Saldar todo"
    expect(find("[data-on-account-payment-target='tenderAmount']").value).to eq("1.533.960,00")
    expect(page).to have_css("[data-on-account-payment-target='balanceAfter']", text: "0,00")

    find("[data-on-account-payment-target='tenderAmount']").set("1534000", clear: :backspace)
    expect(page).to have_css("[data-on-account-payment-target='balanceAfter']", text: "0,00")
    expect(page).to have_css("[data-on-account-payment-target='overpaidLine']", text: "40,00")

    accept_confirm(/Vas a cobrar .*40,00 de más en efectivo/) { click_button "Registrar cobro" }
    expect(page).to have_content("Cobro registrado")
    expect(big.reload.overpaid_amount).to eq(40)
  end

  it "refuses a transfer above the balance" do
    big = create(:order, :on_account, customer: Customer.mostrador, user: create(:user, :vendedor),
                 total_amount: 1_704_400, original_total_amount: 1_704_400)
    create(:order_item, order: big, product: create(:product), quantity: 1, unit_price: 1_704_400)

    visit new_web_payments_on_account_payment_path(big)
    select "Banco Transferencia", from: "tenders[0][payment_method]"
    find("[data-on-account-payment-target='tenderAmount']").set("2000000", clear: :backspace)

    expect(page).to have_content("Es más de lo que debe")
    expect(page).to have_button("Registrar cobro", disabled: true)
  end

  it "keeps submit disabled until a payment method is picked, and Enter does not submit" do
    visit new_web_payments_on_account_payment_path(order)
    amount = find("[data-on-account-payment-target='tenderAmount']")
    amount.set("400", clear: :backspace)
    amount.send_keys(:enter)

    expect(amount.value).to eq("400,00")
    expect(page).to have_button("Registrar cobro", disabled: true)
    expect(page).to have_content("Falta seleccionar el medio de pago")

    select "Efectivo", from: "tenders[0][payment_method]"
    expect(page).to have_button("Registrar cobro", disabled: false)
    expect(Payment.count).to eq(0)
  end

  it "settles with the discounted cash rounded down to the hundred, showing the rounding" do
    big = create(:order, :on_account, customer: Customer.mostrador, user: create(:user, :vendedor),
                 total_amount: 1_704_400, original_total_amount: 1_704_400)
    create(:order_item, order: big, product: create(:product), quantity: 1, unit_price: 1_704_400)

    visit new_web_payments_on_account_payment_path(big)
    select "Efectivo", from: "tenders[0][payment_method]"
    select "10%", from: "discount_percent"
    find("[data-on-account-payment-target='tenderAmount']").set("1533900", clear: :backspace)

    expect(page).to have_css("[data-on-account-payment-target='balanceAfter']", text: "0,00")
    expect(page).to have_css("[data-on-account-payment-target='roundingLine']", text: "60,00")
    expect(page).to have_css("[data-on-account-payment-target='discountLine']", text: "170.440,00")

    accept_confirm(/faltan productos por entregar/) { click_button "Registrar cobro" }
    expect(page).to have_content("Cobro registrado")
    expect(big.reload.outstanding_balance).to eq(0)
  end
end
