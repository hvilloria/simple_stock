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

  describe "payment method card" do
    let!(:movement) do
      create(:cash_movement, source_payment: payment, business_date: date, channel: "mercado_pago",
                             account: "mercado_pago", amount: 264_100)
    end

    before { sign_in caja }

    it "offers to change the method on an open day" do
      get "/web/payments/#{payment.id}"

      card = page_html.at_css("#payment-method")
      expect(card.text).to include("Medio de pago", "Mercado Pago", "Cambiar")
      expect(card.at_css("input[name='payment_method'][value='mercado_pago'][checked]")).to be_present
    end

    it "explains a closed day instead of offering the change" do
      create(:daily_closing, business_date: date)

      get "/web/payments/#{payment.id}"

      card = page_html.at_css("#payment-method")
      expect(card.text).to include("El día 01/10/2026 ya se cerró: el medio de pago no se puede cambiar.")
      expect(card.text).not_to include("Cambiar")
    end

    it "explains a cash discount instead of offering the change" do
      payment.update!(payment_method: "cash")
      movement.update!(channel: "cash", account: "drawer")
      payment.allocations.first.update!(discount_amount: 1_000)

      get "/web/payments/#{payment.id}"

      card = page_html.at_css("#payment-method")
      expect(card.text).to include("Este cobro tuvo descuento en efectivo: no se puede pasar a otro medio.")
      expect(card.text).not_to include("Cambiar")
    end
  end

  describe "PATCH /web/payments/:id/payment_method" do
    let!(:movement) do
      create(:cash_movement, source_payment: payment, business_date: date, channel: "mercado_pago",
                             account: "mercado_pago", amount: 264_100)
    end

    it "changes the method and comes back with a notice" do
      sign_in caja

      patch "/web/payments/#{payment.id}/payment_method", params: { payment_method: "cash" }

      expect(response).to redirect_to("/web/payments/#{payment.id}")
      follow_redirect!
      expect(response.body).to include("Medio de pago actualizado", "Cobro · Efectivo · 264.100,00")
      expect(movement.reload).to have_attributes(channel: "cash", account: "drawer")
    end

    it "re-renders with the error and the form open when the method is unchanged" do
      sign_in caja

      patch "/web/payments/#{payment.id}/payment_method", params: { payment_method: "mercado_pago" }

      expect(response).to have_http_status(:unprocessable_entity)
      card = page_html.at_css("#payment-method")
      expect(card["data-payment-invoice-open-value"]).to eq("true")
      expect(card.text).to include("El cobro ya está registrado con ese medio de pago")
    end

    it "refuses when the day was closed after the page loaded" do
      sign_in caja
      create(:daily_closing, business_date: date)

      patch "/web/payments/#{payment.id}/payment_method", params: { payment_method: "cash" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("El día 01/10/2026 ya se cerró: el medio de pago no se puede cambiar.")
      expect(payment.reload.payment_method).to eq("mercado_pago")
    end

    [ [ "", "No se puede guardar el cobro sin medio de pago" ],
      [ "bitcoin", "Método de pago inválido: bitcoin" ] ].each do |hostile, message|
      it "refuses #{hostile.inspect} as a payment method and writes nothing" do
        sign_in caja

        patch "/web/payments/#{payment.id}/payment_method", params: { payment_method: hostile }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include(message)
        expect(payment.reload.payment_method).to eq("mercado_pago")
        expect(movement.reload).to have_attributes(channel: "mercado_pago", account: "mercado_pago")
      end
    end

    it "keeps the seller out" do
      sign_in create(:user, :vendedor)

      patch "/web/payments/#{payment.id}/payment_method", params: { payment_method: "cash" }

      expect(response).to have_http_status(:redirect)
      expect(payment.reload.payment_method).to eq("mercado_pago")
    end
  end
end
