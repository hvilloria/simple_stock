# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Web::InvoicesController - Filters", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { create(:user, role: "admin") }
  let(:supplier1) { create(:supplier, name: "Supplier A") }
  let(:supplier2) { create(:supplier, name: "Supplier B") }

  before do
    sign_in user
  end

  describe "GET /web/invoices" do
    context "without supplier filter" do
      let!(:invoice1) do
        create(:invoice,
               supplier: supplier1,
               status: "pending",
               amount: 1000,
               currency: "ARS",
               has_items: false,
               invoice_number: "INV-001",
               purchase_date: Date.current,
               due_date: 30.days.from_now.to_date)
      end
      let!(:invoice2) do
        create(:invoice,
               supplier: supplier2,
               status: "pending",
               amount: 2000,
               currency: "ARS",
               has_items: false,
               invoice_number: "INV-002",
               purchase_date: Date.current,
               due_date: 30.days.from_now.to_date)
      end

      it "shows all invoices" do
        get web_invoices_path

        expect(response).to have_http_status(:success)
        expect(response.body).to include(invoice1.invoice_number)
        expect(response.body).to include(invoice2.invoice_number)
      end

      it "shows calculated metrics for all suppliers" do
        get web_invoices_path

        expect(response).to have_http_status(:success)
        # Verify it renders correctly (can't verify assigns in request specs)
        expect(response.body).to include("Deuda Total Pendiente")
      end

      it "shows the supplier dropdown" do
        get web_invoices_path

        expect(response.body).to include("Filtrar por proveedor")
        expect(response.body).to include(supplier1.name)
        expect(response.body).to include(supplier2.name)
      end
    end

    context "with supplier filter" do
      let!(:invoice1) do
        create(:invoice,
               supplier: supplier1,
               status: "pending",
               amount: 1000,
               currency: "ARS",
               has_items: false,
               invoice_number: "INV-001",
               purchase_date: Date.current,
               due_date: 30.days.from_now.to_date)
      end
      let!(:invoice2) do
        create(:invoice,
               supplier: supplier2,
               status: "pending",
               amount: 2000,
               currency: "ARS",
               has_items: false,
               invoice_number: "INV-002",
               purchase_date: Date.current,
               due_date: 30.days.from_now.to_date)
      end

      it "shows only invoices from selected supplier" do
        get web_invoices_path, params: { supplier_id: supplier1.id }

        expect(response).to have_http_status(:success)
        expect(response.body).to include(invoice1.invoice_number)
        expect(response.body).not_to include(invoice2.invoice_number)
      end

      it "shows dropdown with selected supplier" do
        get web_invoices_path, params: { supplier_id: supplier1.id }

        expect(response.body).to include(supplier1.name)
        expect(response.body).to include('selected="selected"')
      end

      it "shows clear filter button" do
        get web_invoices_path, params: { supplier_id: supplier1.id }

        expect(response.body).to include("Limpiar")
      end

      it "filters invoices due this week by supplier" do
        invoice_this_week_s1 = create(:invoice,
                                       supplier: supplier1,
                                       status: "pending",
                                       amount: 500,
                                       currency: "ARS",
                                       has_items: false,
                                       due_date: Date.current,
                                       invoice_number: "INV-TODAY-1")

        invoice_this_week_s2 = create(:invoice,
                                       supplier: supplier2,
                                       status: "pending",
                                       amount: 300,
                                       currency: "ARS",
                                       has_items: false,
                                       due_date: Date.current,
                                       invoice_number: "INV-TODAY-2")

        get web_invoices_path, params: { supplier_id: supplier1.id }

        # Should only show supplier1's invoices
        expect(response).to have_http_status(:success)
        expect(response.body).to include("INV-TODAY-1")
        expect(response.body).not_to include("INV-TODAY-2")
      end
    end

    context "with invalid supplier_id" do
      it "ignores filter and shows all invoices" do
        invoice1 = create(:invoice,
                           supplier: supplier1,
                           status: "pending",
                           has_items: false,
                           invoice_number: "INV-TEST",
                           amount: 1000,
                           currency: "ARS",
                           purchase_date: Date.current,
                           due_date: 30.days.from_now.to_date)

        get web_invoices_path, params: { supplier_id: 99999 }

        expect(response).to have_http_status(:success)
        expect(response.body).to include(invoice1.invoice_number)
        expect(response.body).not_to include("Filtrando por:")
      end
    end

    context "with invoice search filter" do
      let!(:invoice1) do
        create(:invoice,
               supplier: supplier1,
               status: "pending",
               amount: 1000,
               currency: "ARS",
               has_items: false,
               invoice_number: "FAC-001",
               purchase_date: Date.current,
               due_date: 30.days.from_now.to_date)
      end
      let!(:invoice2) do
        create(:invoice,
               supplier: supplier2,
               status: "pending",
               amount: 2000,
               currency: "ARS",
               has_items: false,
               invoice_number: "INV-12345",
               purchase_date: Date.current,
               due_date: 30.days.from_now.to_date)
      end

      it "finds invoices by invoice number" do
        get web_invoices_path, params: { invoice_search: "FAC-001" }

        expect(response).to have_http_status(:success)
        expect(response.body).to include("FAC-001")
        expect(response.body).not_to include("INV-12345")
      end

      it "performs case-insensitive search" do
        get web_invoices_path, params: { invoice_search: "fac-001" }

        expect(response).to have_http_status(:success)
        expect(response.body).to include("FAC-001")
      end

      it "performs partial search" do
        get web_invoices_path, params: { invoice_search: "001" }

        expect(response).to have_http_status(:success)
        expect(response.body).to include("FAC-001")
      end

      it "shows search input field" do
        get web_invoices_path

        expect(response.body).to include('placeholder="🔍 Buscar por N° de factura')
      end
    end

    context "with combined filters (supplier + invoice)" do
      let!(:invoice1) do
        create(:invoice,
               supplier: supplier1,
               status: "pending",
               amount: 1000,
               currency: "ARS",
               has_items: false,
               invoice_number: "FAC-001",
               purchase_date: Date.current,
               due_date: 30.days.from_now.to_date)
      end
      let!(:invoice2) do
        create(:invoice,
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
        get web_invoices_path, params: {
          supplier_id: supplier1.id,
          invoice_search: "FAC-001"
        }

        expect(response).to have_http_status(:success)
        expect(response.body).to include("FAC-001")
        expect(response.body).to include(supplier1.name)
        expect(response.body).not_to include("FAC-002")
      end

      it "shows clear button when filters are active" do
        get web_invoices_path, params: {
          supplier_id: supplier1.id,
          invoice_search: "FAC"
        }

        expect(response.body).to include("Limpiar")
      end
    end
  end

  describe "POST /web/invoices" do
    context "with early payment discount from supplier" do
      let(:supplier_with_discount) do
        create(:supplier,
               name: "Proveedor Descuento",
               payment_term_days: 30,
               early_payment_days: 15,
               early_payment_discount_percentage: 5)
      end

      it "creates invoice inheriting early payment from supplier" do
        post web_invoices_path, params: {
          supplier_id: supplier_with_discount.id,
          invoice_number: "FAC-001",
          amount: "100000",
          currency: "ARS",
          purchase_date: "2026-01-10",
          due_date: "2026-02-10"
        }

        expect(response).to redirect_to(web_invoice_path(Invoice.last))

        invoice = Invoice.last
        expect(invoice.early_payment_due_date).to eq(Date.new(2026, 1, 25)) # 10 + 15 días
        expect(invoice.early_payment_discount_percentage).to eq(5)
      end

      it "creates invoice with manual early payment override" do
        post web_invoices_path, params: {
          supplier_id: supplier_with_discount.id,
          invoice_number: "FAC-002",
          amount: "100000",
          currency: "ARS",
          purchase_date: "2026-01-10",
          due_date: "2026-02-10",
          early_payment_due_date: "2026-01-20",
          early_payment_discount_percentage: "3"
        }

        expect(response).to redirect_to(web_invoice_path(Invoice.last))

        invoice = Invoice.last
        expect(invoice.early_payment_due_date).to eq(Date.new(2026, 1, 20))
        expect(invoice.early_payment_discount_percentage).to eq(3)
      end
    end

    context "with supplier without early payment discount" do
      let(:supplier_no_discount) { create(:supplier, name: "Proveedor Normal") }

      it "creates invoice without early payment terms" do
        post web_invoices_path, params: {
          supplier_id: supplier_no_discount.id,
          invoice_number: "FAC-003",
          amount: "50000",
          currency: "ARS",
          purchase_date: Date.current.to_s,
          due_date: 30.days.from_now.to_date.to_s
        }

        expect(response).to redirect_to(web_invoice_path(Invoice.last))

        invoice = Invoice.last
        expect(invoice.early_payment_due_date).to be_nil
        expect(invoice.early_payment_discount_percentage).to be_nil
      end

      it "creates invoice with manual early payment terms" do
        post web_invoices_path, params: {
          supplier_id: supplier_no_discount.id,
          invoice_number: "FAC-004",
          amount: "50000",
          currency: "ARS",
          purchase_date: "2026-01-15",
          due_date: "2026-02-15",
          early_payment_due_date: "2026-01-25",
          early_payment_discount_percentage: "10"
        }

        expect(response).to redirect_to(web_invoice_path(Invoice.last))

        invoice = Invoice.last
        expect(invoice.early_payment_due_date).to eq(Date.new(2026, 1, 25))
        expect(invoice.early_payment_discount_percentage).to eq(10)
      end
    end
  end

  describe "PATCH /web/invoices/:id" do
    let(:supplier) { create(:supplier, :with_early_payment_discount) }
    let(:invoice) do
      create(:invoice, :simple_mode,
             supplier: supplier,
             status: "pending",
             early_payment_due_date: Date.new(2026, 1, 25),
             early_payment_discount_percentage: 5)
    end

    it "updates early payment due date" do
      patch web_invoice_path(invoice), params: {
        invoice: {
          early_payment_due_date: "2026-01-30"
        }
      }

      expect(response).to redirect_to(web_invoice_path(invoice))
      invoice.reload
      expect(invoice.early_payment_due_date).to eq(Date.new(2026, 1, 30))
    end

    it "updates early payment discount percentage" do
      patch web_invoice_path(invoice), params: {
        invoice: {
          early_payment_discount_percentage: "8"
        }
      }

      expect(response).to redirect_to(web_invoice_path(invoice))
      invoice.reload
      expect(invoice.early_payment_discount_percentage).to eq(8)
    end

    it "removes early payment by setting to empty" do
      patch web_invoice_path(invoice), params: {
        invoice: {
          early_payment_due_date: "",
          early_payment_discount_percentage: ""
        }
      }

      expect(response).to redirect_to(web_invoice_path(invoice))
      invoice.reload
      expect(invoice.early_payment_due_date).to be_nil
      expect(invoice.early_payment_discount_percentage).to be_nil
    end
  end

  describe "POST /web/invoices/:id/mark_as_paid" do
    let(:supplier) { create(:supplier) }

    context "with early payment discount available" do
      let(:invoice) do
        create(:invoice, :simple_mode,
               supplier: supplier,
               status: "pending",
               amount: 10000,
               currency: "ARS",
               early_payment_due_date: 10.days.from_now.to_date,
               early_payment_discount_percentage: 5)
      end

      it "marks as paid with discount applied" do
        post mark_as_paid_web_invoice_path(invoice), params: {
          payment_date: Date.current.to_s,
          apply_discount: "true"
        }

        expect(response).to redirect_to(web_invoice_path(invoice))
        invoice.reload
        expect(invoice.paid_status?).to be true
        expect(invoice.paid_with_discount).to be true
      end

      it "marks as paid without discount" do
        post mark_as_paid_web_invoice_path(invoice), params: {
          payment_date: Date.current.to_s,
          apply_discount: "false"
        }

        expect(response).to redirect_to(web_invoice_path(invoice))
        invoice.reload
        expect(invoice.paid_status?).to be true
        expect(invoice.paid_with_discount).to be false
      end
    end

    context "with expired early payment discount" do
      let(:invoice) do
        create(:invoice, :simple_mode,
               supplier: supplier,
               status: "pending",
               amount: 10000,
               currency: "ARS",
               early_payment_due_date: 5.days.ago.to_date,
               early_payment_discount_percentage: 5)
      end

      it "rejects discount application when expired" do
        post mark_as_paid_web_invoice_path(invoice), params: {
          payment_date: Date.current.to_s,
          apply_discount: "true"
        }

        expect(response).to redirect_to(web_invoice_path(invoice))
        follow_redirect!
        expect(response.body).to include("expiró")
        invoice.reload
        expect(invoice.pending_status?).to be true
      end

      it "allows payment without discount when expired" do
        post mark_as_paid_web_invoice_path(invoice), params: {
          payment_date: Date.current.to_s,
          apply_discount: "false"
        }

        expect(response).to redirect_to(web_invoice_path(invoice))
        invoice.reload
        expect(invoice.paid_status?).to be true
        expect(invoice.paid_with_discount).to be false
      end
    end

    context "without early payment discount configured" do
      let(:invoice) do
        create(:invoice, :simple_mode,
               supplier: supplier,
               status: "pending",
               amount: 10000,
               currency: "ARS",
               early_payment_due_date: nil,
               early_payment_discount_percentage: nil)
      end

      it "marks as paid normally" do
        post mark_as_paid_web_invoice_path(invoice), params: {
          payment_date: Date.current.to_s
        }

        expect(response).to redirect_to(web_invoice_path(invoice))
        invoice.reload
        expect(invoice.paid_status?).to be true
        expect(invoice.paid_with_discount).to be false
      end
    end
  end

  describe "GET /web/invoices/pending" do
    let(:supplier) { create(:supplier) }

    context "with early payment invoices to advance" do
      it "loads invoices with discount expiring before next thursday" do
        # Factura que vence próxima semana pero descuento expira antes del jueves
        early_invoice = create(:invoice, :simple_mode,
                               supplier: supplier,
                               status: "pending",
                               amount: 10000,
                               currency: "ARS",
                               due_date: Date.new(2026, 2, 5),
                               early_payment_due_date: Date.new(2026, 1, 27),
                               early_payment_discount_percentage: 5)

        get pending_web_invoices_path

        expect(response).to have_http_status(:success)
        expect(response.body).to include(early_invoice.invoice_number)
        expect(response.body).to include("Pagos Anticipados")
      end

      it "separates early payment invoices from regular invoices" do
        # Factura con descuento a adelantar
        early_invoice = create(:invoice, :simple_mode,
                               supplier: supplier,
                               status: "pending",
                               amount: 10000,
                               currency: "ARS",
                               due_date: Date.new(2026, 2, 5),
                               early_payment_due_date: Date.new(2026, 1, 27),
                               early_payment_discount_percentage: 5)

        # Factura regular que vence esta semana
        regular_invoice = create(:invoice, :simple_mode,
                                 supplier: supplier,
                                 status: "pending",
                                 amount: 5000,
                                 currency: "ARS",
                                 due_date: Date.current)

        get pending_web_invoices_path

        expect(response).to have_http_status(:success)
        # Ambas deben mostrarse
        expect(response.body).to include(early_invoice.invoice_number)
        expect(response.body).to include(regular_invoice.invoice_number)
      end

      it "excludes early payment invoices from regular invoices section" do
        # Factura que vence esta semana Y tiene descuento a adelantar
        invoice = create(:invoice, :simple_mode,
                         supplier: supplier,
                         status: "pending",
                         amount: 10000,
                         currency: "ARS",
                         due_date: Date.current,
                         early_payment_due_date: Date.current + 2.days,
                         early_payment_discount_percentage: 5)

        get pending_web_invoices_path

        # La factura debe aparecer en Pagos Anticipados
        expect(response.body).to include("Pagos Anticipados")
        expect(response.body).to include(invoice.invoice_number)

        # Pero NO debe aparecer en la sección de Pagos Regulares (suppliers_with_payments)
        # Verificamos que el proveedor no aparece en la sección regular
        expect(response.body).not_to include("Pagos Regulares")
      end
    end

    context "without early payment invoices" do
      it "shows only regular invoices" do
        regular_invoice = create(:invoice, :simple_mode,
                                 supplier: supplier,
                                 status: "pending",
                                 amount: 5000,
                                 currency: "ARS",
                                 due_date: Date.current)

        get pending_web_invoices_path

        expect(response).to have_http_status(:success)
        expect(response.body).to include(regular_invoice.invoice_number)
        expect(response.body).not_to include("Pagos Anticipados")
      end
    end

    context "with period filter" do
      it "filters regular invoices by period but always shows early payment invoices" do
        # Factura con descuento (siempre se muestra)
        early_invoice = create(:invoice, :simple_mode,
                               supplier: supplier,
                               status: "pending",
                               amount: 10000,
                               currency: "ARS",
                               due_date: Date.new(2026, 2, 15),
                               early_payment_due_date: Date.new(2026, 1, 27),
                               early_payment_discount_percentage: 5)

        # Factura de próxima semana (no se muestra con period=this_week)
        next_week_invoice = create(:invoice, :simple_mode,
                                   supplier: supplier,
                                   status: "pending",
                                   amount: 5000,
                                   currency: "ARS",
                                   due_date: Date.current + 1.week)

        get pending_web_invoices_path, params: { period: "this_week" }

        expect(response).to have_http_status(:success)
        # Early payment siempre se muestra
        expect(response.body).to include(early_invoice.invoice_number)
        # Next week no se muestra porque el filtro es this_week
        expect(response.body).not_to include(next_week_invoice.invoice_number)
      end
    end
  end

  describe "POST /web/invoices/mark_supplier_paid" do
    let(:supplier) { create(:supplier) }

    context "with invoices due this week" do
      let!(:invoice1) do
        create(:invoice, :simple_mode,
               supplier: supplier,
               status: "pending",
               amount: 10000,
               currency: "ARS",
               due_date: Date.current)
      end
      let!(:invoice2) do
        create(:invoice, :simple_mode,
               supplier: supplier,
               status: "pending",
               amount: 5000,
               currency: "ARS",
               due_date: Date.current + 1.day)
      end

      it "marks all invoices of the supplier as paid" do
        post mark_supplier_paid_web_invoices_path, params: {
          supplier_id: supplier.id,
          period: "this_week",
          payment_date: Date.current.to_s
        }

        expect(response).to redirect_to(pending_web_invoices_path(period: "this_week"))
        expect(invoice1.reload.paid_status?).to be true
        expect(invoice2.reload.paid_status?).to be true
      end

      it "marks credit notes associated to invoices as applied" do
        cn_associated = create(:credit_note, supplier: supplier, invoice: invoice1, status: "pending")

        post mark_supplier_paid_web_invoices_path, params: {
          supplier_id: supplier.id,
          period: "this_week",
          payment_date: Date.current.to_s
        }

        expect(cn_associated.reload.applied_status?).to be true
      end

      it "marks orphan credit notes (without invoice_id) as applied" do
        orphan_cn = create(:credit_note, supplier: supplier, invoice: nil, status: "pending")

        post mark_supplier_paid_web_invoices_path, params: {
          supplier_id: supplier.id,
          period: "this_week",
          payment_date: Date.current.to_s
        }

        expect(orphan_cn.reload.applied_status?).to be true
        expect(orphan_cn.applied_at).to eq(Date.current)
      end

      it "does not mark orphan credit notes from other suppliers" do
        other_supplier = create(:supplier)
        other_cn = create(:credit_note, supplier: other_supplier, invoice: nil, status: "pending")

        post mark_supplier_paid_web_invoices_path, params: {
          supplier_id: supplier.id,
          period: "this_week",
          payment_date: Date.current.to_s
        }

        expect(other_cn.reload.pending_status?).to be true
      end

      it "includes credit notes count in success message" do
        create(:credit_note, supplier: supplier, invoice: nil, status: "pending")
        create(:credit_note, supplier: supplier, invoice: nil, status: "pending")

        post mark_supplier_paid_web_invoices_path, params: {
          supplier_id: supplier.id,
          period: "this_week",
          payment_date: Date.current.to_s
        }

        follow_redirect!
        expect(response.body).to include("2 nota(s) de crédito aplicada(s)")
      end
    end

    context "with no invoices for supplier" do
      it "redirects with alert" do
        post mark_supplier_paid_web_invoices_path, params: {
          supplier_id: supplier.id,
          period: "this_week"
        }

        expect(response).to redirect_to(pending_web_invoices_path(period: "this_week"))
        follow_redirect!
        expect(response.body).to include("No hay facturas pendientes")
      end
    end
  end
end
