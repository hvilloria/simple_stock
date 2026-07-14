# frozen_string_literal: true

require "rails_helper"

#
# `payment_allocation_controller#recomputeCard` prefills the "Cobrar" amount with
# the nearest-hundred rounding of the discounted total. The backend
# (Payments::AllocatePayment#apply_discounts_for) applies the same rule — but
# ONLY on a full cash settlement with a positive item discount whose submitted
# amount matches the rounded full total within TOLERANCE. This spec drives that
# exact path in a real browser and asserts the persisted values, proving the JS
# prefill and the Ruby rule agree.
#
# Driver, login helpers and Warden reset come from spec/support/system.rb.
# Runs only with FULL=1 (needs Chrome).

RSpec.describe "Cobro de cuenta corriente", type: :system do
  let(:cashier) { create(:user, role: "caja") }
  let(:customer) { create(:customer, :with_credit, name: "Taller Norte") }
  let(:product) { create(:product, name: "Kit de embrague", price_unit: 24_500) }

  # 24.500 − 10% = 22.050 → remainder exactly 50 → ties round DOWN → 22.000.
  let(:discounted_raw) { 22_050 }
  let(:expected_cash) { Payments::CashRounding.round_to_nearest_hundred(discounted_raw) }

  let!(:order) do
    o = create(:order, :pending,
               order_type: "credit",
               customer: customer,
               paper_number: "C-4001",
               total_amount: 24_500,
               original_total_amount: 24_500)
    create(:order_item, order: o, product: product, quantity: 1, unit_price: 24_500, discount_percent: 0)
    o
  end
  let(:item) { order.order_items.first }

  before { login_as(cashier, scope: :user) }

  it "prefills the rounded cash amount and the backend persists the same value" do
    expect(expected_cash).to eq(22_000)

    visit new_web_customer_payment_path(customer)

    check "allocations[0][include]"
    select "10%", from: "allocations[0][discounts][#{item.id}]"

    # The Stimulus prefill must already agree with the Ruby rule.
    expect(page).to have_field("allocations[0][amount]", with: "22.000,00")

    click_button "Registrar Cobro"
    expect(page).to have_content("Cobro de $#{expected_cash} registrado")

    order.reload
    expect(order.total_amount).to eq(expected_cash)
    expect(order.payment_allocations.sum(:amount)).to eq(expected_cash)
    expect(order.outstanding_balance).to eq(0)
    expect(order.status).to eq("confirmed")
    expect(customer.reload.current_balance).to eq(0)
  end
end
