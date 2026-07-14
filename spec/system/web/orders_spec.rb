# frozen_string_literal: true

require "rails_helper"

#
# The unit price is typed into a `currency-input` in AR format (1.500,50) while
# `order_form_controller#updatePrice` mirrors it into the hidden field that is
# actually submitted (purchase_items[][unit_price]). Only a real browser proves
# the visible input and the wire value agree — a request spec would just replay
# what the author believes the form sends.
#
# Driver, login helpers and Warden reset come from spec/support/system.rb.
# Runs only with FULL=1 (needs Chrome).

RSpec.describe "Nueva venta", type: :system do
  let(:vendedor) { create(:user, role: "vendedor") }
  let!(:customer) { create(:customer, name: "Taller Norte") }
  let!(:product) do
    create(:product, name: "Kit de embrague", sku: "KE-0001", price_unit: 100)
  end

  let(:price_input) { "[data-item-index='0'] input[data-controller='currency-input']" }

  before { login_as(vendedor, scope: :user) }

  def add_product_line
    fill_in with: "KE-0001", placeholder: "Buscar por SKU, nombre o marca..."
    find("[data-action='click->product-search#selectProduct']", text: "KE-0001").click
    expect(page).to have_css("[data-item-index='0']")
  end

  it "submits the AR-formatted unit price as a clean number and writes it back to the product" do
    visit new_web_order_path

    select "Taller Norte", from: "Cliente"
    choose "order_type_immediate"
    fill_in "paper_number", with: "0042"
    add_product_line

    find(price_input).set("1.500,50")

    expect(page).to have_button("Crear nota de pedido", disabled: false)
    click_button "Crear nota de pedido"
    expect(page).to have_content("pendiente de cobro")

    order = Order.order(:created_at).last
    expect(order.paper_number).to eq("0042")
    expect(order.customer).to eq(customer)
    expect(order.order_type).to eq("immediate")

    # The wire-format contract: what was typed is what got persisted.
    expect(order.order_items.first.unit_price).to eq(1500.50)
    expect(order.total_amount).to eq(1500.50)

    # Manual pricing + write-back (WORKING_CONTEXT.md → Orders).
    expect(product.reload.price_unit).to eq(1500.50)
  end

  it "keeps submit disabled while a line price is not positive" do
    visit new_web_order_path

    select "Taller Norte", from: "Cliente"
    fill_in "paper_number", with: "0043"
    add_product_line

    find(price_input).set("0")
    expect(page).to have_button("Crear nota de pedido", disabled: true)

    find(price_input).set("1.500,50")
    expect(page).to have_button("Crear nota de pedido", disabled: false)
  end
end
