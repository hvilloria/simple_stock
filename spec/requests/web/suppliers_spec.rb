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

  describe "POST /web/suppliers" do
    it "persists the billed types" do
      post web_suppliers_path, params: { supplier: { name: "AFIP", expense_types: [ "", "taxes", "social_charges" ] } }

      expect(response).to redirect_to(web_suppliers_path)
      expect(Supplier.find_by!(name: "AFIP").expense_types).to eq(%w[taxes social_charges])
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
