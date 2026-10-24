# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Web::Payments::Voids", type: :request do
  let(:caja) { create(:user, :caja) }
  let(:day) { Date.new(2026, 10, 15) }
  let(:order) { create(:order, :on_account, paper_number: "4546", total_amount: 89_000) }

  around { |example| travel_to(day) { example.run } }

  def collect(amount)
    Payments::CollectOnAccount.call(order: order, user: caja, discount_percent: 10,
                                    tenders: [ { payment_method: "cash", amount: amount } ])
    Payment.order(:id).last
  end

  def page_html = Nokogiri::HTML(response.body)

  let!(:first) { collect(40_000) }
  let!(:second) { collect(40_100) }

  before { sign_in caja }

  describe "GET new" do
    it "lists the cascade with its totals and asks for a reason" do
      second.update!(invoice_type: "b", invoice_number: "0003-00012345")

      get "/web/payments/#{first.id}/void/new"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Anular cobro ##{first.id}", "##{second.id}", "80.100,00", "8.900,00",
                                       "El cobro ##{second.id} tiene Factura B · 0003-00012345",
                                       "Motivo *")
      expect(page_html.text.squish).to include(
        "Se anulan este cobro y los que van con él: los posteriores de las mismas notas y, " \
        "en una nota de pedido, todos sus cobros. Las notas vuelven a quedar con saldo y se cobran de nuevo."
      )
      button = page_html.at_css("button[type=submit], input[type=submit]")
      expect(button["data-turbo-confirm"]).to eq("¿Anular 2 cobros por $ 80.100,00?")
    end

    it "shows the discount a sale note collection carried next to its cash" do
      note = create(:order, :pending, order_type: "immediate", paper_number: "5120",
                                      total_amount: 113_000, original_total_amount: 113_000)
      create(:order_item, order: note, quantity: 1, unit_price: 113_000, discount_percent: 0)
      Payments::CollectSaleNote.call(order: note, user: caja, discount_percent: 10,
                                     tenders: [ { payment_method: "cash", amount: 101_700 } ])

      get "/web/payments/#{note.payments.sole.id}/void/new"

      row = page_html.css("tbody tr").sole
      expect(row.css("td").map { |td| td.text.strip }).to include("101.700,00", "11.300,00")
    end

    it "shows the block and no form on a closed day" do
      create(:daily_closing, business_date: day)

      get "/web/payments/#{first.id}/void/new"

      expect(response.body).to include("ese día de caja ya se cerró")
      expect(page_html.at_css("textarea")).to be_nil
    end
  end

  describe "POST create" do
    let(:ids) { [ first.id, second.id ] }

    it "voids the cascade and lands on the payment page" do
      post "/web/payments/#{first.id}/void", params: { reason: "Se anotó mal el monto", payment_ids: ids }

      expect(response).to redirect_to("/web/payments/#{first.id}")
      expect(flash[:notice]).to eq("2 cobros anulados")
      expect(order.reload.outstanding_balance).to eq(89_000)
    end

    it "re-renders with the error when the reason is blank" do
      post "/web/payments/#{first.id}/void", params: { reason: "", payment_ids: ids }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Falta indicar el motivo")
      expect(first.reload).to be_active_status
    end

    it "refuses a stale or forged list" do
      post "/web/payments/#{first.id}/void", params: { reason: "x", payment_ids: [ first.id ] }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Los cobros a anular cambiaron. Revisar la lista.")
    end

    it "refuses a list carrying another customer's payment and voids nothing" do
      stranger = create(:payment, amount: 500)

      post "/web/payments/#{first.id}/void", params: { reason: "x", payment_ids: ids + [ stranger.id ] }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Los cobros a anular cambiaron. Revisar la lista.")
      expect([ first.reload, second.reload, stranger.reload ]).to all(be_active_status)
    end

    it "refuses a payment already voided" do
      post "/web/payments/#{first.id}/void", params: { reason: "x", payment_ids: ids }
      post "/web/payments/#{first.id}/void", params: { reason: "x", payment_ids: [ first.id ] }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Este cobro ya está anulado.")
    end

    it "is not for vendedor" do
      sign_in create(:user, :vendedor)

      post "/web/payments/#{first.id}/void", params: { reason: "x", payment_ids: ids }

      expect(response).to redirect_to(authenticated_root_path)
      expect(first.reload).to be_active_status
    end
  end
end
