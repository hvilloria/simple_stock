require "rails_helper"

RSpec.describe "Invoices", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:user, role: "admin") }
  let(:supplier) { create(:supplier, payment_term_days: 30) }

  before do
    sign_in admin
  end

  describe "POST /web/invoices" do
    context "when creating a invoice in ARS" do
      let(:valid_params) do
        {
          supplier_id: supplier.id,
          invoice_number: "FAC-ARS-001",
          amount: "5000",
          currency: "ARS",
          exchange_rate: "", # Campo vacío cuando es ARS
          purchase_date: Date.today.to_s,
          due_date: 30.days.from_now.to_date.to_s,
          notes: "Test invoice in ARS"
        }
      end

      it "creates a invoice successfully" do
        expect {
          post web_invoices_path, params: valid_params
        }.to change(Invoice, :count).by(1)

        invoice = Invoice.last
        expect(response).to redirect_to(web_invoice_path(invoice))
        follow_redirect!
        expect(response.body).to include("Factura registrada exitosamente")

        expect(invoice.supplier).to eq(supplier)
        expect(invoice.invoice_number).to eq("FAC-ARS-001")
        expect(invoice.amount).to eq(5000)
        expect(invoice.currency).to eq("ARS")
        expect(invoice.exchange_rate).to be_nil
        expect(invoice.status).to eq("pending")
        expect(invoice.has_items).to be false
      end
    end

    context "when creating a invoice in USD" do
      let(:valid_params) do
        {
          supplier_id: supplier.id,
          invoice_number: "FAC-USD-001",
          amount: "1000.00", # Formato limpio que envía JS (ya convertido de argentino)
          currency: "USD",
          exchange_rate: "1200.50", # Formato limpio que envía JS
          purchase_date: Date.today.to_s,
          due_date: 30.days.from_now.to_date.to_s,
          notes: "Test invoice in USD"
        }
      end

      it "creates a invoice successfully" do
        expect {
          post web_invoices_path, params: valid_params
        }.to change(Invoice, :count).by(1)

        invoice = Invoice.last
        expect(response).to redirect_to(web_invoice_path(invoice))
        follow_redirect!
        expect(response.body).to include("Factura registrada exitosamente")

        expect(invoice.supplier).to eq(supplier)
        expect(invoice.invoice_number).to eq("FAC-USD-001")
        expect(invoice.amount).to eq(1000.0)
        expect(invoice.currency).to eq("USD")
        expect(invoice.exchange_rate.to_f).to eq(1200.50)
        expect(invoice.status).to eq("pending")
        expect(invoice.has_items).to be false
      end
    end

    context "when creating a invoice in USD without exchange_rate" do
      let(:invalid_params) do
        {
          supplier_id: supplier.id,
          invoice_number: "FAC-USD-002",
          amount: "1000",
          currency: "USD",
          exchange_rate: "", # Falta exchange_rate para USD
          purchase_date: Date.today.to_s,
          due_date: 30.days.from_now.to_date.to_s
        }
      end

      it "fails with validation error" do
        expect {
          post web_invoices_path, params: invalid_params
        }.not_to change(Invoice, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("Exchange rate required for USD invoices")
      end
    end

    context "when creating a invoice with invalid amount" do
      let(:invalid_params) do
        {
          supplier_id: supplier.id,
          invoice_number: "FAC-001",
          amount: "0",
          currency: "ARS",
          purchase_date: Date.today.to_s,
          due_date: 30.days.from_now.to_date.to_s
        }
      end

      it "fails with validation error" do
        expect {
          post web_invoices_path, params: invalid_params
        }.not_to change(Invoice, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("Amount must be greater than zero")
      end
    end

    context "when creating a invoice with formatted amount from frontend" do
      it "handles amount correctly (formato limpio JS: 154400.80)" do
        params = {
          supplier_id: supplier.id,
          invoice_number: "FAC-FORMAT-001",
          amount: "154400.80", # JavaScript ya convirtió de "154.400,80" a "154400.80"
          currency: "ARS",
          purchase_date: Date.today.to_s,
          due_date: 30.days.from_now.to_date.to_s
        }

        expect {
          post web_invoices_path, params: params
        }.to change(Invoice, :count).by(1)

        invoice = Invoice.last
        expect(invoice.amount).to be_within(0.01).of(154400.80)
      end

      it "handles large amount correctly (formato limpio JS: 1500000.50)" do
        params = {
          supplier_id: supplier.id,
          invoice_number: "FAC-FORMAT-002",
          amount: "1500000.50", # JavaScript ya convirtió de "1.500.000,50" a "1500000.50"
          currency: "ARS",
          purchase_date: Date.today.to_s,
          due_date: 30.days.from_now.to_date.to_s
        }

        expect {
          post web_invoices_path, params: params
        }.to change(Invoice, :count).by(1)

        invoice = Invoice.last
        expect(invoice.amount).to be_within(0.01).of(1500000.50)
      end

      it "handles amount with two decimal places (formato limpio JS: 999.99)" do
        params = {
          supplier_id: supplier.id,
          invoice_number: "FAC-FORMAT-003",
          amount: "999.99", # JavaScript ya convirtió de "999,99" a "999.99"
          currency: "ARS",
          purchase_date: Date.today.to_s,
          due_date: 30.days.from_now.to_date.to_s
        }

        expect {
          post web_invoices_path, params: params
        }.to change(Invoice, :count).by(1)

        invoice = Invoice.last
        expect(invoice.amount).to be_within(0.01).of(999.99)
      end
    end
  end
end
