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
          exchange_rate: "", # Empty field when it is ARS
          purchase_date: Date.current.to_s,
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
          amount: "1000.00", # Clean format sent by JS (already converted from Argentine)
          currency: "USD",
          exchange_rate: "1200.50", # Clean format sent by JS
          purchase_date: Date.current.to_s,
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
          exchange_rate: "", # Missing exchange_rate for USD
          purchase_date: Date.current.to_s,
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
          purchase_date: Date.current.to_s,
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
          amount: "154400.80", # JavaScript already converted from "154.400,80" to "154400.80"
          currency: "ARS",
          purchase_date: Date.current.to_s,
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
          amount: "1500000.50", # JavaScript already converted from "1.500.000,50" to "1500000.50"
          currency: "ARS",
          purchase_date: Date.current.to_s,
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
          amount: "999.99", # JavaScript already converted from "999,99" to "999.99"
          currency: "ARS",
          purchase_date: Date.current.to_s,
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

  # Money values POSTed straight at the endpoint, bypassing Stimulus. The backend must
  # normalize correctly or reject — never book a wrong number.
  describe "POST /web/invoices — hostile amount" do
    def post_amount(amount)
      post web_invoices_path, params: {
        supplier_id: supplier.id,
        invoice_number: "FAC-HOSTILE-#{SecureRandom.hex(3)}",
        amount: amount,
        currency: "ARS",
        exchange_rate: "",
        purchase_date: Date.current.to_s,
        due_date: 30.days.from_now.to_date.to_s
      }
    end

    it "persists 1500000.50 for the Argentine format '1.500.000,50'" do
      expect { post_amount("1.500.000,50") }.to change(Invoice, :count).by(1)

      expect(Invoice.last.amount).to eq(BigDecimal("1500000.50"))
    end

    it "persists 1500000 for the Argentine thousands '1.500.000'" do
      expect { post_amount("1.500.000") }.to change(Invoice, :count).by(1)

      expect(Invoice.last.amount).to eq(1_500_000)
    end

    it "persists 1500.50 for the clean decimal '1500.50'" do
      expect { post_amount("1500.50") }.to change(Invoice, :count).by(1)

      expect(Invoice.last.amount).to eq(BigDecimal("1500.50"))
    end

    it "rejects a non-numeric amount instead of booking zero" do
      expect { post_amount("abc") }.not_to change(Invoice, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "rejects a negative amount" do
      expect { post_amount("-500") }.not_to change(Invoice, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "rejects a blank amount" do
      expect { post_amount("") }.not_to change(Invoice, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "POST /web/invoices — hostile exchange_rate" do
    def post_rate(rate)
      post web_invoices_path, params: {
        supplier_id: supplier.id,
        invoice_number: "FAC-RATE-#{SecureRandom.hex(3)}",
        amount: "1000",
        currency: "USD",
        exchange_rate: rate,
        purchase_date: Date.current.to_s,
        due_date: 30.days.from_now.to_date.to_s
      }
    end

    it "persists 1200.50 for the Argentine format '1.200,50'" do
      expect { post_rate("1.200,50") }.to change(Invoice, :count).by(1)

      expect(Invoice.last.exchange_rate).to eq(BigDecimal("1200.50"))
    end

    # A single dot is the decimal separator, so a bare "1.200" is 1.2 — not 1200. The real
    # form never submits it: currency-input reformats it to "1.200,00" on blur, which parses
    # to 1200. Pinned so nobody "fixes" the parser into stripping single dots, which would
    # turn every clean "1500.50" into 150050.
    it "treats a single dot as a decimal separator ('1.200' -> 1.2)" do
      expect { post_rate("1.200") }.to change(Invoice, :count).by(1)

      expect(Invoice.last.exchange_rate).to eq(BigDecimal("1.2"))
    end

    it "persists 1200.50 for the clean decimal '1200.50'" do
      expect { post_rate("1200.50") }.to change(Invoice, :count).by(1)

      expect(Invoice.last.exchange_rate).to eq(BigDecimal("1200.50"))
    end

    it "rejects a non-numeric exchange rate instead of booking zero" do
      expect { post_rate("abc") }.not_to change(Invoice, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "rejects a negative exchange rate" do
      expect { post_rate("-500") }.not_to change(Invoice, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /web/invoices/:id/cancel" do
    it "cancels a pending simple invoice without creating stock movements" do
      invoice = create(:invoice, :simple_mode, supplier: supplier)

      expect {
        patch cancel_web_invoice_path(invoice)
      }.not_to change(StockMovement, :count)

      expect(response).to redirect_to(web_invoices_path)
      expect(invoice.reload.status).to eq("cancelled")

      follow_redirect!
      expect(response.body).to include("Factura cancelada exitosamente")
    end

    it "rejects cancelling an invoice that is already paid" do
      invoice = create(:invoice, :paid, supplier: supplier)

      patch cancel_web_invoice_path(invoice)

      expect(response).to have_http_status(:redirect)
      expect(invoice.reload.status).to eq("paid")
    end
  end
end
