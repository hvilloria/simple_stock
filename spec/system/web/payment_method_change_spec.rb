# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Cambiar el medio de pago de un cobro", type: :system do
  include Warden::Test::Helpers

  let(:admin) { create(:user, :admin) }
  let(:date) { Date.current }
  let(:payment) { create(:payment, payment_method: "cash", amount: 60_000, payment_date: date) }

  before do
    create(:cash_movement, source_payment: payment, business_date: date, amount: 60_000,
                           channel: "cash", account: "drawer", description: "Cobro QA38")
    driven_by :selenium_chrome_headless, screen_size: [ 1400, 900 ]
    login_as(admin, scope: :user)
  end

  after { Warden.test_reset! }

  it "moves a cash collection to Mercado Pago and the day follows" do
    visit web_payment_path(payment)
    within("#payment-method") do
      click_button "Cambiar"
      find("label", text: "Mercado Pago").click
      click_button "Guardar medio de pago"
    end

    expect(page).to have_content("Medio de pago actualizado")
    expect(page).to have_content("Cobro · Mercado Pago · 60.000,00")

    visit web_cash_day_path(date)
    expect(page).to have_css("[data-group='mercado_pago']", text: "60.000,00")
    expect(page).to have_css("[data-group='efectivo']", text: "0,00")
  end

  it "closes the form without saving on Cancelar" do
    visit web_payment_path(payment)
    within("#payment-method") do
      click_button "Cambiar"
      click_button "Cancelar"
      expect(page).to have_button("Cambiar")
    end
    expect(payment.reload.payment_method).to eq("cash")
  end
end
