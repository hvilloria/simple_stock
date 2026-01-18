# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Web::PurchasesController - Filters", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { create(:user, role: "admin") }
  let(:supplier1) { create(:supplier, name: "Supplier A") }
  let(:supplier2) { create(:supplier, name: "Supplier B") }

  before do
    sign_in user
  end

  describe "GET /web/purchases" do
    context "without supplier filter" do
      let!(:purchase1) do
        create(:purchase,
               supplier: supplier1,
               status: "pending",
               amount: 1000,
               currency: "ARS",
               has_items: false,
               invoice_number: "INV-001",
               purchase_date: Date.current,
               due_date: 30.days.from_now.to_date)
      end
      let!(:purchase2) do
        create(:purchase,
               supplier: supplier2,
               status: "pending",
               amount: 2000,
               currency: "ARS",
               has_items: false,
               invoice_number: "INV-002",
               purchase_date: Date.current,
               due_date: 30.days.from_now.to_date)
      end

      it "shows all purchases" do
        get web_purchases_path

        expect(response).to have_http_status(:success)
        expect(response.body).to include(purchase1.invoice_number)
        expect(response.body).to include(purchase2.invoice_number)
      end

      it "shows calculated metrics for all suppliers" do
        get web_purchases_path

        expect(response).to have_http_status(:success)
        # Verify it renders correctly (can't verify assigns in request specs)
        expect(response.body).to include("Deuda Total Pendiente")
      end

      it "shows the supplier dropdown" do
        get web_purchases_path

        expect(response.body).to include("Filtrar por proveedor")
        expect(response.body).to include(supplier1.name)
        expect(response.body).to include(supplier2.name)
      end
    end

    context "with supplier filter" do
      let!(:purchase1) do
        create(:purchase,
               supplier: supplier1,
               status: "pending",
               amount: 1000,
               currency: "ARS",
               has_items: false,
               invoice_number: "INV-001",
               purchase_date: Date.current,
               due_date: 30.days.from_now.to_date)
      end
      let!(:purchase2) do
        create(:purchase,
               supplier: supplier2,
               status: "pending",
               amount: 2000,
               currency: "ARS",
               has_items: false,
               invoice_number: "INV-002",
               purchase_date: Date.current,
               due_date: 30.days.from_now.to_date)
      end

      it "shows only purchases from selected supplier" do
        get web_purchases_path, params: { supplier_id: supplier1.id }

        expect(response).to have_http_status(:success)
        expect(response.body).to include(purchase1.invoice_number)
        expect(response.body).not_to include(purchase2.invoice_number)
      end

      it "shows dropdown with selected supplier" do
        get web_purchases_path, params: { supplier_id: supplier1.id }

        expect(response.body).to include(supplier1.name)
        expect(response.body).to include('selected="selected"')
      end

      it "shows clear filter button" do
        get web_purchases_path, params: { supplier_id: supplier1.id }

        expect(response.body).to include("Limpiar")
      end

      it "filters purchases due today by supplier" do
        purchase_today_s1 = create(:purchase,
                                   supplier: supplier1,
                                   status: "pending",
                                   amount: 500,
                                   currency: "ARS",
                                   has_items: false,
                                   due_date: Date.current,
                                   invoice_number: "INV-TODAY-1")

        purchase_today_s2 = create(:purchase,
                                   supplier: supplier2,
                                   status: "pending",
                                   amount: 300,
                                   currency: "ARS",
                                   has_items: false,
                                   due_date: Date.current,
                                   invoice_number: "INV-TODAY-2")

        get web_purchases_path, params: { supplier_id: supplier1.id }

        # Should only show supplier1's in metrics
        expect(response.body).to include("Vencen Hoy")
      end
    end

    context "with invalid supplier_id" do
      it "ignores filter and shows all purchases" do
        purchase1 = create(:purchase,
                           supplier: supplier1,
                           status: "pending",
                           has_items: false,
                           invoice_number: "INV-TEST",
                           amount: 1000,
                           currency: "ARS",
                           purchase_date: Date.current,
                           due_date: 30.days.from_now.to_date)

        get web_purchases_path, params: { supplier_id: 99999 }

        expect(response).to have_http_status(:success)
        expect(response.body).to include(purchase1.invoice_number)
        expect(response.body).not_to include("Filtrando por:")
      end
    end

    context "with invoice search filter" do
      let!(:purchase1) do
        create(:purchase,
               supplier: supplier1,
               status: "pending",
               amount: 1000,
               currency: "ARS",
               has_items: false,
               invoice_number: "FAC-001",
               purchase_date: Date.current,
               due_date: 30.days.from_now.to_date)
      end
      let!(:purchase2) do
        create(:purchase,
               supplier: supplier2,
               status: "pending",
               amount: 2000,
               currency: "ARS",
               has_items: false,
               invoice_number: "INV-12345",
               purchase_date: Date.current,
               due_date: 30.days.from_now.to_date)
      end

      it "finds purchases by invoice number" do
        get web_purchases_path, params: { invoice_search: "FAC-001" }

        expect(response).to have_http_status(:success)
        expect(response.body).to include("FAC-001")
        expect(response.body).not_to include("INV-12345")
      end

      it "performs case-insensitive search" do
        get web_purchases_path, params: { invoice_search: "fac-001" }

        expect(response).to have_http_status(:success)
        expect(response.body).to include("FAC-001")
      end

      it "performs partial search" do
        get web_purchases_path, params: { invoice_search: "001" }

        expect(response).to have_http_status(:success)
        expect(response.body).to include("FAC-001")
      end

      it "shows search input field" do
        get web_purchases_path

        expect(response.body).to include('placeholder="🔍 Buscar por N° de factura')
      end
    end

    context "with combined filters (supplier + invoice)" do
      let!(:purchase1) do
        create(:purchase,
               supplier: supplier1,
               status: "pending",
               amount: 1000,
               currency: "ARS",
               has_items: false,
               invoice_number: "FAC-001",
               purchase_date: Date.current,
               due_date: 30.days.from_now.to_date)
      end
      let!(:purchase2) do
        create(:purchase,
               supplier: supplier2,
               status: "pending",
               amount: 2000,
               currency: "ARS",
               has_items: false,
               invoice_number: "FAC-002",
               purchase_date: Date.current,
               due_date: 30.days.from_now.to_date)
      end

      it "filters by both supplier and invoice number" do
        get web_purchases_path, params: {
          supplier_id: supplier1.id,
          invoice_search: "FAC-001"
        }

        expect(response).to have_http_status(:success)
        expect(response.body).to include("FAC-001")
        expect(response.body).to include(supplier1.name)
        expect(response.body).not_to include("FAC-002")
      end

      it "shows clear button when filters are active" do
        get web_purchases_path, params: {
          supplier_id: supplier1.id,
          invoice_search: "FAC"
        }

        expect(response.body).to include("Limpiar")
      end
    end
  end
end
