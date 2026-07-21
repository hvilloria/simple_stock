# frozen_string_literal: true

require "rails_helper"

# System test for the early-payment fields in /web/invoices/new.
#
# Prerequisites:
#   - Google Chrome installed (uses :selenium_chrome_headless driver)
#
# What is tested here:
#   Switching from a supplier WITH an early-payment discount to one WITHOUT it
#   must not persist the first supplier's discount. The discount inputs are only
#   hidden via CSS, so stale values would still be submitted with the form.

RSpec.describe "New invoice — early payment fields reset on supplier change", type: :system do
  include Warden::Test::Helpers

  let(:admin) { create(:user, role: "admin") }

  let!(:supplier_with_discount) do
    create(:supplier, :with_early_payment_discount,
           name: "Proveedor Con Descuento",
           payment_term_days: 30)
  end

  let!(:supplier_without_discount) do
    create(:supplier,
           name: "Proveedor Sin Descuento",
           payment_term_days: 30,
           early_payment_days: nil,
           early_payment_discount_percentage: nil)
  end

  before do
    driven_by :selenium_chrome_headless, screen_size: [ 1400, 900 ]
    login_as(admin, scope: :user)
  end

  after { Warden.test_reset! }

  it "does not persist the previous supplier's discount" do
    visit new_web_invoice_path

    # First pick the supplier that HAS a discount, so the JS fills the inputs.
    select supplier_with_discount.name, from: "supplier_id"
    expect(page).to have_css("[data-invoice-form-target='earlyPaymentSection']", visible: true)

    # Then switch to the supplier without one — the section hides.
    select supplier_without_discount.name, from: "supplier_id"
    expect(page).to have_css("[data-invoice-form-target='earlyPaymentSection']", visible: :hidden)

    fill_in "invoice_number", with: "FA-RESET-001"
    fill_in "amount", with: "100000"

    click_button "Registrar Factura"

    expect(page).to have_content("Factura registrada exitosamente.")

    invoice = Invoice.find_by!(invoice_number: "FA-RESET-001")
    expect(invoice.supplier).to eq(supplier_without_discount)
    expect(invoice.early_payment_discount_percentage).to be_blank
    expect(invoice.early_payment_due_date).to be_nil
  end
end
