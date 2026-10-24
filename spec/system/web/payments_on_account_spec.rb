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

    expect(page).to have_css("[data-on-account-payment-target='discountLabel']", text: "Gana de descuento (10%)")
    expect(page).to have_css("[data-on-account-payment-target='discountLine']", text: "80.000,00")
    expect(page).to have_css("[data-on-account-payment-target='balanceAfter']", text: "824.400,00")

    click_button "Saldar todo"
    expect(find("[data-on-account-payment-target='tenderAmount']").value).to eq("1.533.900,00")
    expect(page).to have_css("[data-on-account-payment-target='roundingLine']", text: "60,00")
    expect(page).to have_css("[data-on-account-payment-target='balanceAfter']", text: "0,00")

    find("[data-on-account-payment-target='tenderAmount']").set("1534000", clear: :backspace)
    expect(page).to have_css("[data-on-account-payment-target='balanceAfter']", text: "0,00")
    expect(page).to have_css("[data-on-account-payment-target='overpaidLine']", text: "40,00")

    accept_confirm(/Se cobrará .*40,00 de más en efectivo/) { click_button "Registrar cobro" }
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

  it "opens the second cash collection with the previous discount and the cash to charge" do
    honda = create(:order, :on_account, customer: Customer.mostrador, user: create(:user, :vendedor),
                   total_amount: 89_000, original_total_amount: 89_000)
    create(:order_item, order: honda, product: create(:product), quantity: 1, unit_price: 89_000)

    visit new_web_payments_on_account_payment_path(honda)
    expect(page).to have_select("discount_percent", selected: "0%")
    expect(page).to have_no_content("El cobro anterior fue con")
    expect(page).to have_no_css("[data-on-account-payment-target='cashToChargeRow']", visible: true)

    select "Efectivo", from: "tenders[0][payment_method]"
    find("[data-on-account-payment-target='tenderAmount']").set("40000", clear: :backspace)
    select "10%", from: "discount_percent"
    expect(page).to have_css("[data-on-account-payment-target='balanceAfter']", text: "45.000,00")
    click_button "Registrar cobro"
    expect(page).to have_content("Cobro registrado")

    visit new_web_payments_on_account_payment_path(honda)
    expect(page).to have_select("discount_percent", selected: "10%")
    expect(page).to have_content("El cobro anterior fue con 10%")
    expect(page).to have_css("[data-on-account-payment-target='cashToChargeLabel']", text: "En efectivo con 10%")
    expect(page).to have_css("[data-on-account-payment-target='cashToChargeLine']", text: "40.100,00")
    expect(page).to have_button(text: /Saldar todo: cobrar .*40\.100,00/)

    select "Efectivo", from: "tenders[0][payment_method]"
    click_button "Saldar todo"
    expect(find("[data-on-account-payment-target='tenderAmount']").value).to eq("40.100,00")
    expect(page).to have_css("[data-on-account-payment-target='balanceAfter']", text: "0,00")

    accept_confirm(/faltan productos por entregar/) { click_button "Registrar cobro" }
    expect(page).to have_content("Cobro registrado")
    expect(honda.reload.outstanding_balance).to eq(0)
    expect(honda.total_amount).to eq(80_100)
  end

  it "falls back to the exact settle-all cash when the hundred floor is zero" do
    tiny = create(:order, :on_account, customer: Customer.mostrador, user: create(:user, :vendedor),
                  total_amount: 50, original_total_amount: 50)
    create(:order_item, order: tiny, product: create(:product), quantity: 1, unit_price: 50)

    visit new_web_payments_on_account_payment_path(tiny)
    select "Efectivo", from: "tenders[0][payment_method]"
    select "10%", from: "discount_percent"
    click_button "Saldar todo"

    expect(find("[data-on-account-payment-target='tenderAmount']").value).to eq("45,00")
    expect(page).to have_css("[data-on-account-payment-target='cashToChargeLine']", text: "45,00")
  end

  it "drops the preselected discount when a non-cash method is added" do
    visit new_web_payments_on_account_payment_path(order)
    select "Efectivo", from: "tenders[0][payment_method]"
    find("[data-on-account-payment-target='tenderAmount']").set("400", clear: :backspace)
    select "10%", from: "discount_percent"
    click_button "Registrar cobro"
    expect(page).to have_content("Cobro registrado")

    visit new_web_payments_on_account_payment_path(order)
    expect(page).to have_select("discount_percent", selected: "10%")
    expect(page).to have_css("[data-on-account-payment-target='cashToChargeRow']", visible: true)

    select "Banco Transferencia", from: "tenders[0][payment_method]"
    expect(page).to have_select("discount_percent", selected: "0%", disabled: true)
    expect(page).to have_no_css("[data-on-account-payment-target='cashToChargeRow']", visible: true)
  end

  describe "after note 4647's first 250.000 in cash at 10%" do
    let!(:note) do
      o = create(:order, :on_account, customer: Customer.mostrador, user: create(:user, :vendedor),
                 total_amount: 532_000, original_total_amount: 532_000)
      create(:order_item, order: o, product: create(:product), quantity: 1, unit_price: 532_000)
      Payments::CollectOnAccount.call(user: admin, order: o, discount_percent: 10,
                                      tenders: [ { payment_method: "cash", amount: 250_000 } ])
      o
    end

    it "shows note 4647's account and the cash to settle" do
      visit new_web_payments_on_account_payment_path(note)

      expect(page).to have_content(/Resta pagar\s+\$282\.000,00/)
      expect(page).to have_content(/Descuento ya ganado\s+−\$25\.000,00/)
      expect(page).to have_content(/En digital\s+\$257\.000,00/)
      expect(page).to have_no_content("Debe hoy")
      expect(page).to have_no_content("Baja la deuda en")

      select "Efectivo", from: "tenders[0][payment_method]"
      select "10%", from: "discount_percent"
      expect(page).to have_css("[data-on-account-payment-target='cashToChargeLabel']", text: "En efectivo con 10%")
      expect(page).to have_css("[data-on-account-payment-target='cashToChargeLine']", text: "228.800,00")
      expect(page).to have_button(text: /Saldar todo: cobrar .*228\.800,00/)

      click_button "Saldar todo"
      expect(page).to have_css("[data-on-account-payment-target='discountLabel']", text: "Descuento 10% de lo que resta")
      expect(page).to have_css("[data-on-account-payment-target='discountLine']", text: "28.200,00")
      expect(page).to have_css("[data-on-account-payment-target='balanceAfter']", text: "0,00")
      expect(page).to have_no_css("[data-on-account-payment-target='remainingAfterRow']", visible: true)
      expect(page).to have_no_css("[data-on-account-payment-target='earnedAfterRow']", visible: true)
    end

    it "previews a partial and what is left after it" do
      visit new_web_payments_on_account_payment_path(note)
      select "Efectivo", from: "tenders[0][payment_method]"
      select "10%", from: "discount_percent"
      find("[data-on-account-payment-target='tenderAmount']").set("100000", clear: :backspace)

      expect(page).to have_css("[data-on-account-payment-target='discountLabel']", text: "Gana de descuento (10%)")
      expect(page).to have_css("[data-on-account-payment-target='discountLine']", text: "10.000,00")
      expect(page).to have_content(/Después de este cobro/i)
      expect(page).to have_css("[data-on-account-payment-target='remainingAfterLine']", text: "182.000,00")
      expect(page).to have_css("[data-on-account-payment-target='earnedAfterLine']", text: /−\$\s?35\.000,00/)
      expect(page).to have_content("Queda debiendo")
      expect(page).to have_css("[data-on-account-payment-target='balanceAfter']", text: "147.000,00")
    end
  end

  it "shows the server's cash-to-settle amount when it has cents" do
    odd = create(:order, :on_account, customer: Customer.mostrador, user: create(:user, :vendedor),
                 total_amount: 12_345, original_total_amount: 12_345)
    create(:order_item, order: odd, product: create(:product), quantity: 1, unit_price: 12_345)
    expected = ActiveSupport::NumberHelper.number_to_currency(
      odd.cash_settle_amount(10), unit: "", separator: ",", delimiter: "."
    )
    expect(expected).to eq("11.110,50")

    visit new_web_payments_on_account_payment_path(odd)
    select "Efectivo", from: "tenders[0][payment_method]"
    select "10%", from: "discount_percent"

    expect(page).to have_css("[data-on-account-payment-target='cashToChargeLine']", text: expected)
    click_button "Saldar todo"
    expect(find("[data-on-account-payment-target='tenderAmount']").value).to eq("11.100,00")
  end
end
