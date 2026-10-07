# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Credit account collection", type: :system do
  include Warden::Test::Helpers

  let(:caja) { create(:user, :caja) }
  let(:customer) { create(:customer, :with_credit) }
  let!(:order) do
    o = create(:order, :credit_order, :pending, customer: customer, paper_number: "CC-1",
               total_amount: 80_300, original_total_amount: 80_300)
    create(:order_item, order: o, product: create(:product), quantity: 1, unit_price: 80_300)
    o
  end

  before do
    driven_by :selenium_chrome_headless, screen_size: [ 1400, 900 ]
    login_as(caja, scope: :user)
  end

  after { Warden.test_reset! }

  it "flags cash above the balance on the card and confirms it" do
    visit new_web_customer_payment_path(customer)
    find("[data-role='include-checkbox']").check
    find("[data-role='amount-input']").set("80400", clear: :backspace)

    expect(page).to have_css("[data-role='overpaid-line']", text: "Cobrado de más")
    expect(page).to have_css("[data-payment-allocation-target='remainingBalance']", text: "$0")

    accept_confirm(/Vas a cobrar de más en efectivo/) { click_button "Registrar Cobro" }
    expect(page).to have_current_path(web_customer_path(customer), ignore_query: true)
    expect(order.reload.overpaid_amount).to eq(100)
  end

  it "blocks a transfer above the balance" do
    visit new_web_customer_payment_path(customer)
    find("[data-role='include-checkbox']").check
    find("[data-role='method-select']").select("Banco Transferencia")
    find("[data-role='amount-input']").set("80400", clear: :backspace)

    expect(page).to have_css("[data-role='overpaid-error']", visible: :visible)
    expect(page).to have_button("Registrar Cobro", disabled: true)
  end
end
