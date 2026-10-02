# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Caja - facturar un cobro", type: :system do
  include Warden::Test::Helpers

  let(:admin) { create(:user, :admin) }
  let(:date) { Date.current }
  let(:payment) { create(:payment, payment_method: "mercado_pago", amount: 264_100, payment_date: date) }

  before do
    order = create(:order, customer: payment.customer, paper_number: "4429", total_amount: 264_100)
    create(:payment_allocation, payment: payment, order: order, amount: 264_100)
    create(:cash_movement, business_date: date, source_payment: payment, channel: "mercado_pago",
                           account: "mercado_pago", amount: 264_100, user: admin)
    login_as(admin, scope: :user)
  end

  it "invoices a collection from the cash day and shows it back on the row" do
    visit "/web/cash/days/#{date}"
    within("#day-entries") { click_link "Facturar" }

    expect(page).to have_button("Guardar factura")
    choose "Factura B", allow_label_click: true
    fill_in "Número", with: "1455"
    click_button "Guardar factura"

    expect(page).to have_content("Factura guardada")
    expect(page).to have_content("Factura B · 1455")

    click_link "← Caja del #{date.strftime('%d/%m/%Y')}"
    expect(find("#day-entries")).to have_content("B · 1455")
  end

  it "hides the number for a collection with no invoice and saves it" do
    visit "/web/payments/#{payment.id}?facturar=1"

    choose "Factura B", allow_label_click: true
    expect(page).to have_field("Número")

    choose "Sin factura", allow_label_click: true
    expect(page).to have_no_field("Número")
    click_button "Guardar factura"

    expect(page).to have_content("Factura guardada")
    expect(page).to have_no_button("Guardar factura")
    expect(find("#payment-invoice")).to have_content("Sin factura")
  end
end
