# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Paying an invoice from its page", type: :system do
  include Warden::Test::Helpers

  let(:admin) { create(:user, :admin) }
  let!(:invoice) do
    create(:invoice, :simple_mode, :in_ars, supplier: create(:supplier, name: "AFIP"), amount: 250_000,
           expense_type: "taxes", invoice_number: "IIBB 09/2026", purchase_date: Date.current - 5)
  end

  before do
    driven_by :selenium_chrome_headless
    login_as(admin, scope: :user)
  end

  after { Warden.test_reset! }

  it "enables confirm only after an origin is picked and writes the outflow" do
    visit web_invoice_path(invoice)
    click_button "Pagar", match: :first

    within "#payInvoiceModal" do
      expect(page).to have_button("Confirmar pago", disabled: true)
      find("label", text: "Caja grande").click
      expect(page).to have_text("Sale de Caja grande")
      click_button "Confirmar pago"
    end

    expect(page).to have_text("Salió $ 250.000,00 de Caja grande")
    expect(invoice.reload.cash_movement).to have_attributes(account: "main_cash", amount: -250_000)
  end
end
