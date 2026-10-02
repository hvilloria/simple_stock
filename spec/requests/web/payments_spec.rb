# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Web::Payments", type: :request do
  let(:caja) { create(:user, :caja) }
  let(:date) { Date.new(2026, 10, 1) }
  let(:payment) { create(:payment, payment_method: "mercado_pago", amount: 264_100, payment_date: date) }
  let!(:order) do
    create(:order, customer: payment.customer, paper_number: "4429", total_amount: 264_100).tap do |o|
      create(:payment_allocation, payment: payment, order: o, amount: 264_100)
    end
  end

  def page_html = Nokogiri::HTML(response.body)

  describe "GET /web/payments/:id" do
    before { sign_in caja }

    it "shows the payment, the notes it covers and its cash movement" do
      create(:cash_movement, source_payment: payment, business_date: date, channel: "mercado_pago",
                             account: "mercado_pago", amount: 264_100)

      get "/web/payments/#{payment.id}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Cobro · Mercado Pago · 264.100,00", "4429", "Caja del 01/10/2026", "Día abierto")
      expect(page_html.at_css("#payment-invoice").text).to include("Sin facturar", "Facturar")
    end

    it "opens the invoice form when asked to invoice" do
      get "/web/payments/#{payment.id}", params: { facturar: 1 }

      expect(page_html.at_css("#payment-invoice")["data-payment-invoice-open-value"]).to eq("true")
    end

    it "shows the recorded invoice with a way to correct it" do
      payment.update!(invoice_type: "b", invoice_number: "1452")

      get "/web/payments/#{payment.id}"

      expect(page_html.at_css("#payment-invoice").text).to include("Factura B · 1452", "Corregir")
    end

    it "says when the collection was reversed" do
      create(:cash_movement, source_payment: payment, business_date: date, amount: 264_100)
      travel_to(date + 2) do
        create(:cash_movement, source_payment: payment, business_date: date + 2, amount: -264_100)
      end

      get "/web/payments/#{payment.id}"

      expect(response.body).to include("Este cobro se revirtió el 03/10/2026 porque se anuló la venta.")
    end

    it "falls back to the payment date when the payment has no cash movement" do
      get "/web/payments/#{payment.id}"

      expect(response.body).to include("Caja del 01/10/2026", "Sin movimiento de caja")
    end

    it "keeps the seller out" do
      sign_in create(:user, :vendedor)

      get "/web/payments/#{payment.id}"

      expect(response).to have_http_status(:redirect)
    end
  end

  describe "PATCH /web/payments/:id" do
    before { sign_in caja }

    it "records the invoice and goes back to the payment" do
      patch "/web/payments/#{payment.id}", params: { invoice_type: "b", invoice_number: "1452" }

      expect(response).to redirect_to("/web/payments/#{payment.id}")
      expect(flash[:notice]).to eq("Factura guardada")
      expect(payment.reload.invoice_label).to eq("Factura B · 1452")
    end

    it "re-renders the open form with the error when the number is missing" do
      patch "/web/payments/#{payment.id}", params: { invoice_type: "a", invoice_number: "" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("El número es obligatorio para Factura A o B")
      expect(page_html.at_css("#payment-invoice")["data-payment-invoice-open-value"]).to eq("true")
      expect(payment.reload).not_to be_billed
    end

    it "does not let a vendedor record an invoice" do
      sign_in create(:user, :vendedor)

      patch "/web/payments/#{payment.id}", params: { invoice_type: "b", invoice_number: "1452" }

      expect(response).to have_http_status(:redirect)
      expect(payment.reload).not_to be_billed
    end
  end
end
