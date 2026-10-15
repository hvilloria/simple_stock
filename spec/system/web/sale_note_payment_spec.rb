# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Sale note collection", type: :system do
  include Warden::Test::Helpers

  let(:caja) { create(:user, :caja) }
  let!(:note) do
    o = create(:order, :pending, order_type: "immediate", paper_number: "SN-1",
               total_amount: 80_300, original_total_amount: 80_300)
    create(:order_item, order: o, product: create(:product), quantity: 1, unit_price: 80_300)
    o
  end

  before do
    driven_by :selenium_chrome_headless, screen_size: [ 1400, 900 ]
    login_as(caja, scope: :user)
  end

  after { Warden.test_reset! }

  it "shows the exact discounted total and confirms cash above it" do
    visit new_web_sale_note_payment_path(note)
    select "10%", from: "discount_percent"
    select "Efectivo", from: "tenders[0][payment_method]"

    expect(page).to have_css("[data-sale-note-payment-target='summaryTotal']", text: "72.270,00")
    find("[data-sale-note-payment-target='tenderAmount']").set("72300", clear: :backspace)
    expect(page).to have_css("[data-sale-note-payment-target='summaryDiffLabel']", text: "Cobrado de más")
    expect(page).to have_css("[data-sale-note-payment-target='summaryDiff']", text: "30,00")

    accept_confirm(/Vas a cobrar .*30,00 de más en efectivo/) { click_button "Confirmar cobro" }
    expect(page).to have_content("Nota SN-1 cobrada")
    expect(note.reload.total_amount).to eq(72_300)
  end

  it "rounds a half-cent discounted total up, like the server" do
    odd = create(:order, :pending, order_type: "immediate", paper_number: "SN-2",
                 total_amount: 1_234.50, original_total_amount: 1_234.50)
    create(:order_item, order: odd, product: create(:product), quantity: 1, unit_price: 1_234.50)

    visit new_web_sale_note_payment_path(odd)
    select "5%", from: "discount_percent"
    select "Efectivo", from: "tenders[0][payment_method]"

    expect(page).to have_css("[data-sale-note-payment-target='summaryTotal']", text: "1.172,78")
    expect(find("[data-sale-note-payment-target='tenderAmount']").value).to eq("1.172,78")

    click_button "Confirmar cobro"
    expect(page).to have_content("Nota SN-2 cobrada")
    odd.reload
    expect(odd.total_amount).to eq(BigDecimal("1172.78"))
    expect(odd.outstanding_balance).to eq(0)
    expect(odd.status).to eq("confirmed")
  end

  it "keeps submit disabled below the total" do
    visit new_web_sale_note_payment_path(note)
    find("[data-sale-note-payment-target='tenderAmount']").set("80000", clear: :backspace)
    expect(page).to have_button("Confirmar cobro", disabled: true)
  end

  it "keeps submit disabled until a payment method is picked" do
    visit new_web_sale_note_payment_path(note)
    expect(page).to have_select("tenders[0][payment_method]", selected: "Seleccionar medio")

    find("[data-sale-note-payment-target='tenderAmount']").set("80300", clear: :backspace)
    expect(page).to have_button("Confirmar cobro", disabled: true)
    expect(page).to have_content("Falta seleccionar el medio de pago")

    select "Mercado Pago", from: "tenders[0][payment_method]"
    expect(page).to have_button("Confirmar cobro", disabled: false)
    expect(page).to have_no_content("Falta seleccionar el medio de pago")
  end

  it "starts an added method row without a method" do
    visit new_web_sale_note_payment_path(note)
    select "Efectivo", from: "tenders[0][payment_method]"
    click_button "+ Agregar método"

    expect(page).to have_select("tenders[1][payment_method]", selected: "Seleccionar medio")
  end

  it "formats the amount on Enter instead of submitting" do
    visit new_web_sale_note_payment_path(note)
    select "Efectivo", from: "tenders[0][payment_method]"
    amount = find("[data-sale-note-payment-target='tenderAmount']")
    amount.set("80300", clear: :backspace)
    amount.send_keys(:enter)

    expect(amount.value).to eq("80.300,00")
    expect(page).to have_button("Confirmar cobro", disabled: false)
    expect(Payment.count).to eq(0)
    expect(note.reload.status).to eq("pending")
  end

  it "accepts the discounted total rounded down to the hundred as a rounding" do
    visit new_web_sale_note_payment_path(note)
    select "10%", from: "discount_percent"
    select "Efectivo", from: "tenders[0][payment_method]"
    amount = find("[data-sale-note-payment-target='tenderAmount']")

    amount.set("72100", clear: :backspace)
    expect(page).to have_button("Confirmar cobro", disabled: true)
    expect(page).to have_content(/Con descuento se puede redondear hasta \$\s72\.200,00\./)

    amount.set("72200", clear: :backspace)
    expect(page).to have_css("[data-sale-note-payment-target='summaryDiffLabel']", text: "Redondeo")
    expect(page).to have_css("[data-sale-note-payment-target='summaryDiff']", text: "70,00")
    expect(page).to have_no_content("Con descuento se puede redondear")

    click_button "Confirmar cobro"
    expect(page).to have_content("Nota SN-1 cobrada")
    expect(note.reload.total_amount).to eq(72_200)
  end

  it "asks for the number only on Factura A or B and blocks submit without it" do
    visit new_web_sale_note_payment_path(note)
    select "Banco Tarjeta", from: "tenders[0][payment_method]"
    find("[data-sale-note-payment-target='tenderAmount']").set("80300", clear: :backspace)
    expect(page).to have_no_field("tenders[0][invoice_number]")

    select "Factura B", from: "tenders[0][invoice_type]"
    expect(page).to have_field("tenders[0][invoice_number]")
    expect(page).to have_button("Confirmar cobro", disabled: true)
    expect(page).to have_content("Falta el número de factura")

    fill_in "tenders[0][invoice_number]", with: "1452"
    expect(page).to have_button("Confirmar cobro", disabled: false)
    expect(page).to have_no_content("Falta el número de factura")

    click_button "Confirmar cobro"
    expect(page).to have_content("Nota SN-1 cobrada")
    expect(note.reload.payments.sole.invoice_label).to eq("Factura B · 1452")
  end

  it "clears the number when the row goes back to no invoice" do
    visit new_web_sale_note_payment_path(note)
    select "Efectivo", from: "tenders[0][payment_method]"
    find("[data-sale-note-payment-target='tenderAmount']").set("80300", clear: :backspace)
    select "Factura A", from: "tenders[0][invoice_type]"
    fill_in "tenders[0][invoice_number]", with: "55"

    select "Factura", from: "tenders[0][invoice_type]"
    expect(page).to have_no_field("tenders[0][invoice_number]")

    click_button "Confirmar cobro"
    expect(page).to have_content("Nota SN-1 cobrada")
    expect(note.reload.payments.sole).to have_attributes(invoice_type: nil, invoice_number: nil)
  end

  it "starts an added method row without an invoice" do
    visit new_web_sale_note_payment_path(note)
    select "Factura B", from: "tenders[0][invoice_type]"
    fill_in "tenders[0][invoice_number]", with: "9"
    click_button "+ Agregar método"

    expect(page).to have_select("tenders[1][invoice_type]", selected: "Factura")
    expect(page).to have_no_field("tenders[1][invoice_number]")
  end

  [ [ 1280, 800 ], [ 1366, 768 ] ].each do |width, height|
    it "does not overflow the page horizontally at #{width}x#{height} with an invoice number" do
      visit new_web_sale_note_payment_path(note)
      page.current_window.resize_to(width, height)
      select "Banco Transferencia", from: "tenders[0][payment_method]"
      select "Factura B", from: "tenders[0][invoice_type]"

      expect(page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")).to be(true)
    end
  end
end
