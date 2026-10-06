# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Web::Suppliers", type: :request do
  let(:admin) { create(:user, role: "admin") }

  before { sign_in admin }

  describe "GET /web/suppliers/new" do
    it "offers the four types with only Proveedor checked" do
      get new_web_supplier_path

      html = Nokogiri::HTML(response.body)
      boxes = html.css("input[type=checkbox][name='supplier[expense_types][]']")
      expect(boxes.map { |box| box["value"] }).to eq(%w[supplier taxes utilities social_charges])
      expect(boxes.select { |box| box["checked"] }.map { |box| box["value"] }).to eq([ "supplier" ])
      expect(response.body).to include("Qué factura", "Proveedor", "Impuestos", "Servicios", "Cargas sociales")
    end
  end

  describe "initial state of the optional cards" do
    def cards(supplier)
      get edit_web_supplier_path(supplier)
      Nokogiri::HTML(response.body).css("fieldset[data-supplier-form-target=card]").to_h { |card| [ card["data-section"], card ] }
    end

    it "renders both cards hidden when the supplier has no values" do
      cards = cards(create(:supplier))

      expect(cards.values.map { |card| card.key?("hidden") }).to all(be true)
      expect(cards.values.map { |card| card.key?("disabled") }).to all(be false)
    end

    it "renders a card with values open" do
      cards = cards(create(:supplier, bank_alias: "MI.ALIAS"))

      expect(cards["bank"].key?("hidden")).to be false
      expect(cards["terms"].key?("hidden")).to be true
    end

    it "renders the cards hidden and disabled for a taxes-only supplier" do
      cards = cards(create(:supplier, expense_types: %w[taxes], bank_alias: "AFIP"))

      expect(cards.values.map { |card| card.key?("hidden") }).to all(be true)
      expect(cards.values.map { |card| card.key?("disabled") }).to all(be true)
    end
  end

  describe "POST /web/suppliers" do
    it "persists the billed types" do
      post web_suppliers_path, params: { supplier: { name: "AFIP", expense_types: [ "", "taxes", "social_charges" ] } }

      expect(response).to redirect_to(web_suppliers_path)
      expect(Supplier.find_by!(name: "AFIP").expense_types).to eq(%w[taxes social_charges])
    end

    it "creates a taxes-only supplier without payment fields" do
      post web_suppliers_path, params: { supplier: { name: "AFIP", expense_types: [ "", "taxes", "social_charges" ],
                                                      payment_term_days: "", early_payment_days: "",
                                                      early_payment_discount_percentage: "" } }

      expect(response).to redirect_to(web_suppliers_path)
      expect(Supplier.find_by!(name: "AFIP").payment_term_days).to be_nil
    end

    it "refuses a payment term on a taxes-only supplier" do
      expect {
        post web_suppliers_path, params: { supplier: { name: "AFIP", expense_types: [ "", "taxes" ], payment_term_days: "30" } }
      }.not_to change(Supplier, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Las condiciones de pago solo corresponden a proveedores o servicios")
    end

    it "refuses a supplier that bills nothing" do
      expect {
        post web_suppliers_path, params: { supplier: { name: "Nada", expense_types: [ "" ] } }
      }.not_to change(Supplier, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Elegí al menos un tipo de factura")
    end
  end

  describe "GET /web/suppliers/:id/edit" do
    it "checks the types the supplier bills" do
      supplier = create(:supplier, expense_types: %w[utilities taxes])

      get edit_web_supplier_path(supplier)

      checked = Nokogiri::HTML(response.body).css("input[type=checkbox][name='supplier[expense_types][]'][checked]")
      expect(checked.map { |box| box["value"] }).to contain_exactly("utilities", "taxes")
    end
  end

  describe "PATCH /web/suppliers/:id" do
    let!(:supplier) { create(:supplier) }

    it "updates the billed types" do
      patch web_supplier_path(supplier), params: { supplier: { expense_types: [ "", "supplier", "utilities" ] } }

      expect(response).to redirect_to(web_supplier_path(supplier))
      expect(supplier.reload.expense_types).to eq(%w[supplier utilities])
    end

    it "clears the stale payment terms when it stops billing Proveedor and Servicios" do
      supplier.update!(payment_term_days: 30, early_payment_days: 10, early_payment_discount_percentage: 5)

      patch web_supplier_path(supplier), params: { supplier: { expense_types: [ "", "taxes" ] } }

      expect(response).to redirect_to(web_supplier_path(supplier))
      supplier.reload
      expect(supplier.expense_types).to eq(%w[taxes])
      expect([ supplier.payment_term_days, supplier.early_payment_days, supplier.early_payment_discount_percentage ]).to all(be_nil)
    end

    it "refuses payment terms posted for a taxes-only supplier" do
      patch web_supplier_path(supplier), params: { supplier: { expense_types: [ "", "taxes" ], payment_term_days: "30" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Las condiciones de pago solo corresponden a proveedores o servicios")
    end

    it "keeps the payment terms when expense types are not posted" do
      supplier.update!(payment_term_days: 30)

      patch web_supplier_path(supplier), params: { supplier: { email: "a@b.com" } }

      expect(supplier.reload.payment_term_days).to eq(30)
    end

    it "refuses to leave the supplier billing nothing" do
      patch web_supplier_path(supplier), params: { supplier: { expense_types: [ "" ] } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Elegí al menos un tipo de factura")
      expect(supplier.reload.expense_types).to eq([ "supplier" ])
    end

    it "refuses an unknown type" do
      patch web_supplier_path(supplier), params: { supplier: { expense_types: [ "rent" ] } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(supplier.reload.expense_types).to eq([ "supplier" ])
    end
  end

  describe "GET /web/suppliers/:id" do
    it "shows the types billed" do
      supplier = create(:supplier, expense_types: %w[taxes social_charges])

      get web_supplier_path(supplier)

      expect(response.body).to include("Factura:", "Impuestos · Cargas sociales")
    end
  end
end
