# frozen_string_literal: true

require "rails_helper"

#
# `sale_note_payment_controller.js` duplicates two backend rules on values that
# get submitted:
#   1. cash-only discount (Payments::CollectSaleNote#validate!)
#   2. nearest-hundred rounding of the discounted cash total, which is prefilled
#      into the tender input by the JS helper `roundToNearestHundred` and
#      re-derived server-side by Payments::CashRounding — two independent
#      implementations of one rule.
#
# Driver, login helpers and Warden reset come from spec/support/system.rb.
# Runs only with FULL=1 (needs Chrome).

RSpec.describe "Cobro de nota de pedido", type: :system do
  let(:cashier) { create(:user, role: "caja") }
  let(:product) { create(:product, name: "Kit de embrague", price_unit: 24_500) }

  # 24.500 × 0,90 = 22.050 → remainder exactly 50 → ties round DOWN → 22.000.
  let(:discounted_raw) { 22_050 }
  let(:expected_cash) { Payments::CashRounding.round_to_nearest_hundred(discounted_raw) }

  let!(:note) do
    o = create(:order, :pending,
               order_type: "immediate",
               paper_number: "G-3001",
               total_amount: 24_500,
               original_total_amount: 24_500)
    create(:order_item, order: o, product: product, quantity: 1, unit_price: 24_500, discount_percent: 0)
    o
  end

  before { login_as(cashier, scope: :user) }

  it "rounds the discounted cash total to the nearest hundred, ties DOWN" do
    expect(expected_cash).to eq(22_000)

    visit new_web_sale_note_payment_path(note)
    select "10%", from: "discount_percent"

    # The Stimulus prefill must already agree with the Ruby rule.
    expect(page).to have_field("tenders[0][amount]", with: "22.000,00")

    click_button "Confirmar cobro"
    expect(page).to have_content("cobrada")

    note.reload
    expect(note.total_amount).to eq(expected_cash)
    expect(note.payment_allocations.sum(:amount)).to eq(expected_cash)
    expect(note.outstanding_balance).to eq(0)
    expect(note.status).to eq("confirmed")
  end

  it "forces the discount back to 0 when a tender is not cash (cash-only rule)" do
    visit new_web_sale_note_payment_path(note)

    select "10%", from: "discount_percent"
    expect(page).to have_field("tenders[0][amount]", with: "22.000,00")

    select Payment.method_label("bank_transfer"), from: "tenders[0][payment_method]"

    expect(page).to have_select("discount_percent", selected: "0%")
    expect(page).to have_button("Confirmar cobro", disabled: true)
    expect(note.reload.status).to eq("pending")
  end
end
