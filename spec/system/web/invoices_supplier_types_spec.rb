# frozen_string_literal: true

require "rails_helper"

# The supplier select offers only the suppliers that bill the chosen invoice
# type. The server-side rules live in the model and request specs.
RSpec.describe "Proveedores según el tipo de factura", type: :system do
  include Warden::Test::Helpers

  let(:admin)     { create(:user, role: "admin") }
  let!(:goods)    { create(:supplier, name: "Taiwan Quality Auto Supply", payment_term_days: 30) }
  let!(:afip)     { create(:supplier, name: "AFIP", expense_types: %w[taxes social_charges]) }
  let!(:edesur)   { create(:supplier, name: "Edesur", expense_types: %w[utilities]) }
  let!(:mixed)    { create(:supplier, name: "Contadora Mixta", expense_types: %w[supplier taxes], early_payment_days: 10, early_payment_discount_percentage: 5) }

  before do
    driven_by :selenium_chrome_headless, screen_size: [ 1400, 900 ]
    login_as(admin, scope: :user)
  end

  def option_state(select_id, name)
    option = find("##{select_id}").find("option", text: name, visible: :all)
    option.disabled? ? :disabled : :enabled
  end

  describe "new invoice" do
    before { visit "/web/invoices/new" }

    it "offers merchandise suppliers under Proveedor and not the tax authority" do
      expect(option_state("supplier_id", "Taiwan Quality Auto Supply")).to eq(:enabled)
      expect(option_state("supplier_id", "AFIP")).to eq(:disabled)
    end

    it "swaps the offered suppliers when the type changes" do
      choose "Impuestos", allow_label_click: true

      expect(option_state("supplier_id", "AFIP")).to eq(:enabled)
      expect(option_state("supplier_id", "Edesur")).to eq(:disabled)
      expect(option_state("supplier_id", "Taiwan Quality Auto Supply")).to eq(:disabled)

      choose "Proveedor", allow_label_click: true

      expect(option_state("supplier_id", "Taiwan Quality Auto Supply")).to eq(:enabled)
      expect(option_state("supplier_id", "AFIP")).to eq(:disabled)
    end

    it "clears a supplier that does not bill the new type and its payment term" do
      select "Taiwan Quality Auto Supply", from: "supplier_id"
      expect(page).to have_text("Plazo: 30 días")

      choose "Servicios", allow_label_click: true

      expect(find("#supplier_id").value).to eq("")
      expect(page).to have_no_text("Plazo: 30 días")
      select "Edesur", from: "supplier_id"
    end

    it "keeps the supplier when it bills the new type" do
      choose "Impuestos", allow_label_click: true
      select "AFIP", from: "supplier_id"

      choose "Cargas sociales", allow_label_click: true

      expect(find("#supplier_id").value).to eq(afip.id.to_s)
    end

    it "offers the early-payment discount under Proveedor and hides it under Impuestos" do
      select "Contadora Mixta", from: "supplier_id"
      expect(page).to have_css("[data-invoice-form-target='earlyPaymentSection']", visible: :visible)

      choose "Impuestos", allow_label_click: true
      expect(page).to have_css("[data-invoice-form-target='earlyPaymentSection']", visible: :hidden)
      expect(find("#early_payment_discount_percentage", visible: :all).value).to eq("")

      choose "Proveedor", allow_label_click: true
      expect(page).to have_css("[data-invoice-form-target='earlyPaymentSection']", visible: :visible)
    end

    it "registers a tax invoice for the tax authority by period and detail" do
      choose "Impuestos", allow_label_click: true
      select "AFIP", from: "supplier_id"
      fill_in "detail", with: "IVA"
      fill_in "amount", with: "250.000,00"

      click_button "Registrar Factura"

      expect(page).to have_text("Factura registrada exitosamente")
      expect(page).to have_text("Factura IVA · #{Date.current.prev_month.strftime('%m/%Y')}")
      expect(Invoice.last).to have_attributes(supplier: afip, expense_type: "taxes", detail: "IVA", invoice_number: nil,
                                              period: Date.current.prev_month.beginning_of_month, currency: "ARS")
    end

    it "shows the number for a supplier and the period and detail for the other types" do
      expect(page).to have_field("invoice_number")
      expect(page).to have_no_field("period")
      expect(page).to have_no_field("detail")
      expect(page).to have_field("currency_ars", visible: :all)

      choose "Impuestos", allow_label_click: true

      expect(page).to have_no_field("invoice_number")
      expect(page).to have_field("period", with: Date.current.prev_month.strftime("%Y-%m"))
      expect(page).to have_field("detail")
      expect(page).to have_no_field("currency_usd", visible: :visible)

      choose "Proveedor", allow_label_click: true

      expect(page).to have_field("invoice_number")
      expect(page).to have_no_field("period")
      expect(page).to have_field("currency_usd", visible: :all)
    end

    it "puts the currency back to pesos when the type stops being supplier" do
      choose "currency_usd"
      expect(page).to have_field("exchange_rate")

      choose "Servicios", allow_label_click: true

      expect(find("#currency_ars", visible: :all)).to be_checked
      expect(page).to have_no_field("exchange_rate")
    end

    it "keeps the period and detail when the server refuses the registration" do
      choose "Impuestos", allow_label_click: true
      select "AFIP", from: "supplier_id"
      fill_in "detail", with: "IVA"
      fill_in "amount", with: "0,00"

      click_button "Registrar Factura"

      expect(page).to have_text("Amount must be greater than zero")
      expect(page).to have_field("detail", with: "IVA")
      expect(page).to have_field("period", with: Date.current.prev_month.strftime("%Y-%m"))
      expect(page).to have_no_field("invoice_number")
    end
  end

  describe "edit invoice whose supplier stopped billing its type" do
    let!(:legacy) { create(:supplier, name: "Ex Proveedor", expense_types: %w[supplier]) }
    let!(:invoice) { create(:invoice, :simple_mode, :in_ars, supplier: legacy, expense_type: "supplier") }

    before do
      legacy.update!(expense_types: %w[taxes])
      visit "/web/invoices/#{invoice.id}/edit"
    end

    it "keeps the current supplier selectable and selected after toggling the type away and back" do
      expect(find("#invoice_supplier_id").value).to eq(legacy.id.to_s)

      select "Impuestos", from: "invoice_expense_type"
      select "Proveedor", from: "invoice_expense_type"

      expect(option_state("invoice_supplier_id", "Ex Proveedor")).to eq(:enabled)
      expect(find("#invoice_supplier_id").value).to eq(legacy.id.to_s)
    end
  end

  describe "edit invoice" do
    let!(:invoice) { create(:invoice, :simple_mode, :in_ars, supplier: goods, expense_type: "supplier") }

    before { visit "/web/invoices/#{invoice.id}/edit" }

    it "offers the suppliers of the current type and keeps the current one" do
      expect(find("#invoice_supplier_id").value).to eq(goods.id.to_s)
      expect(option_state("invoice_supplier_id", "AFIP")).to eq(:disabled)
    end

    it "swaps the number for the period and detail when the type changes" do
      expect(page).to have_field("invoice_invoice_number")
      expect(page).to have_no_field("invoice_period")

      select "Impuestos", from: "invoice_expense_type"

      expect(page).to have_no_field("invoice_invoice_number")
      expect(page).to have_field("invoice_period")
      expect(page).to have_field("invoice_detail")

      select "Proveedor", from: "invoice_expense_type"

      expect(page).to have_field("invoice_invoice_number")
      expect(page).to have_no_field("invoice_period")
    end

    it "clears the supplier when the new type is not billed by it" do
      select "Impuestos", from: "invoice_expense_type"

      expect(find("#invoice_supplier_id").value).to eq("")
      expect(option_state("invoice_supplier_id", "AFIP")).to eq(:enabled)
      expect(option_state("invoice_supplier_id", "Taiwan Quality Auto Supply")).to eq(:disabled)
    end
  end
end
