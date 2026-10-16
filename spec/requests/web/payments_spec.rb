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

  describe "GET /web/payments" do
    around { |example| travel_to(date) { example.run } }

    it "lists today's collections with their totals" do
      sign_in caja

      get "/web/payments"

      expect(response).to have_http_status(:ok)
      row = page_html.at_css("tbody tr")
      expect(row.text).to include("##{payment.id}", "4429", "Mercado Pago", "264.100,00", "Vigente")
      expect(page_html.at_css("[data-payments-totals]").text).to include("Mercado Pago", "Total", "264.100,00")
    end

    it "shows voided collections dimmed, outside the totals" do
      voided = create(:payment, :voided, customer: payment.customer, amount: 50_000, payment_date: date)
      create(:voided_payment_allocation, payment: voided, order: order, amount: 50_000)
      sign_in caja

      get "/web/payments", params: { status: "all" }

      voided_row = page_html.css("tbody tr").find { |tr| tr.text.include?("##{voided.id}") }
      expect(voided_row.text).to include("Anulado", "Monto mal cargado")
      expect(page_html.at_css("[data-payments-totals]").text).not_to include("50.000,00")
    end

    it "lists a collection reversed by a sale cancellation as voided, outside the totals" do
      reversed = create(:payment, customer: payment.customer, payment_method: "cash", amount: 50_000, payment_date: date)
      cancelled = create(:order, customer: payment.customer, paper_number: "5106", total_amount: 50_000)
      create(:payment_allocation, payment: reversed, order: cancelled, amount: 50_000)
      create(:cash_movement, source_payment: reversed, business_date: date, amount: 50_000)
      expect(Sales::CancelOrder.call(order: cancelled, user: caja).success?).to be true
      sign_in caja

      get "/web/payments"

      expect(page_html.css("tbody tr").map(&:text).join).not_to include("##{reversed.id}")
      expect(page_html.at_css("[data-payments-totals]").text).not_to include("50.000,00")

      get "/web/payments", params: { status: "voided" }

      row = page_html.css("tbody tr").find { |tr| tr.text.include?("##{reversed.id}") }
      expect(row.text).to include("Anulado", "Venta anulada", "5106")
      expect(page_html.at_css("[data-payments-totals]").text).not_to include("50.000,00")

      get "/web/payments/#{reversed.id}"

      expect(response.body).to include("Motivo: Venta anulada")
      expect(response.body).not_to include("Anular cobro")
    end

    it "shows the empty state" do
      sign_in caja

      get "/web/payments", params: { period: "yesterday" }

      expect(response.body).to include("No hay cobros para estos filtros. Probar con otro período o quitar los filtros.")
    end

    it "ignores a malformed custom range and hostile filters" do
      sign_in caja

      get "/web/payments", params: { period: "custom", from: "31/02/2026", to: "x", payment_method: "'; DROP", status: "zzz" }

      expect(response).to have_http_status(:ok)
      expect(page_html.at_css("tbody tr").text).to include("##{payment.id}")
    end

    it "is not for vendedor" do
      sign_in create(:user, :vendedor)

      get "/web/payments"

      expect(response).to redirect_to(authenticated_root_path)
    end
  end

  describe "GET /web/payments/:id" do
    before { sign_in caja }

    it "shows the payment, the notes it covers and its cash movement" do
      create(:cash_movement, source_payment: payment, business_date: date, channel: "mercado_pago",
                             account: "mercado_pago", amount: 264_100)

      get "/web/payments/#{payment.id}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Cobro · Mercado Pago · 264.100,00", "4429", "01/10/2026", "Día abierto")
      expect(page_html.at_css("#payment-invoice").text).to include("Sin facturar", "Facturar")
    end

    it "goes back to Cobros and offers to void an active collection" do
      get "/web/payments/#{payment.id}"

      expect(page_html.css("a[href='/web/payments']").map(&:text).join).to include("← Cobros")
      expect(page_html.at_css("a[href='/web/payments/#{payment.id}/void/new']").text).to include("Anular cobro")
    end

    it "shows a voided collection without actions" do
      voider = create(:user, :caja, name: "Caja Turno Tarde")
      create(:voided_payment_allocation, payment: payment, order: order, amount: 264_100)
      order.payment_allocations.destroy_all
      payment.update!(status: "voided", voided_at: Time.zone.local(2026, 10, 2, 10), voided_by: voider,
                      void_reason: "Monto mal cargado")

      get "/web/payments/#{payment.id}"

      expect(response.body).to include("Anulado", "Cobro anulado el 02/10/2026 por Caja Turno Tarde. Motivo: Monto mal cargado",
                                       "Notas que cubría", "4429")
      expect(response.body).not_to include("Anular cobro", "Facturar")
    end

    it "opens the invoice form when asked to invoice" do
      get "/web/payments/#{payment.id}", params: { facturar: 1 }

      expect(page_html.at_css("#payment-invoice")["data-payment-invoice-open-value"]).to eq("true")
    end

    it "keeps the invoice card closed on a voided payment even when asked to invoice" do
      payment.update!(status: "voided", voided_at: Time.current, voided_by: caja, void_reason: "x")

      get "/web/payments/#{payment.id}", params: { facturar: 1 }

      expect(page_html.at_css("#payment-invoice")["data-payment-invoice-open-value"]).to eq("false")
    end

    it "shows the recorded invoice with a way to correct it" do
      payment.update!(invoice_type: "b", invoice_number: "1452")

      get "/web/payments/#{payment.id}"

      expect(page_html.at_css("#payment-invoice").text).to include("Factura B · 1452", "Corregir")
    end

    it "says so when the payment has no cash movement" do
      get "/web/payments/#{payment.id}"

      expect(response.body).to include("Sin movimiento de caja")
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

    it "refuses a voided payment and keeps the invoice card closed" do
      payment.update!(status: "voided", voided_at: Time.current, voided_by: caja, void_reason: "x")

      patch "/web/payments/#{payment.id}", params: { invoice_type: "b", invoice_number: "1452" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("El cobro está anulado")
      expect(page_html.at_css("#payment-invoice")["data-payment-invoice-open-value"]).to eq("false")
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

    it "refuses a voided payment without opening the form" do
      sign_in caja
      payment.update!(status: "voided", voided_at: Time.current, voided_by: caja, void_reason: "x")

      patch "/web/payments/#{payment.id}/payment_method", params: { payment_method: "cash" }

      expect(response).to have_http_status(:unprocessable_entity)
      card = page_html.at_css("#payment-method")
      expect(card["data-payment-invoice-open-value"]).to eq("false")
      expect(card.text).to include("El cobro está anulado")
      expect(response.body).not_to include("Guardar medio de pago")
      expect(card.text).not_to include("Cambiar")
      expect(payment.reload.payment_method).to eq("mercado_pago")
    end

    it "keeps the seller out" do
      sign_in create(:user, :vendedor)

      patch "/web/payments/#{payment.id}/payment_method", params: { payment_method: "cash" }

      expect(response).to have_http_status(:redirect)
      expect(payment.reload.payment_method).to eq("mercado_pago")
    end
  end
end
