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

    it "registers a tax invoice for the tax authority" do
      choose "Impuestos", allow_label_click: true
      select "AFIP", from: "supplier_id"
      fill_in "invoice_number", with: "IIBB 09/2026"
      choose "currency_ars"
      fill_in "amount", with: "250.000,00"

      click_button "Registrar Factura"

      expect(page).to have_text("Factura registrada exitosamente")
      expect(Invoice.last).to have_attributes(supplier: afip, expense_type: "taxes")
    end
  end

  describe "edit invoice" do
    let!(:invoice) { create(:invoice, :simple_mode, :in_ars, supplier: goods, expense_type: "supplier") }

    before { visit "/web/invoices/#{invoice.id}/edit" }

    it "offers the suppliers of the current type and keeps the current one" do
      expect(find("#invoice_supplier_id").value).to eq(goods.id.to_s)
      expect(option_state("invoice_supplier_id", "AFIP")).to eq(:disabled)
    end

    it "clears the supplier when the new type is not billed by it" do
      select "Impuestos", from: "invoice_expense_type"

      expect(find("#invoice_supplier_id").value).to eq("")
      expect(option_state("invoice_supplier_id", "AFIP")).to eq(:enabled)
      expect(option_state("invoice_supplier_id", "Taiwan Quality Auto Supply")).to eq(:disabled)
    end
  end
end
