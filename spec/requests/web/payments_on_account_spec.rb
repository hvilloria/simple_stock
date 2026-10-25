require "rails_helper"

RSpec.describe "Web::PaymentsOnAccount", type: :request do
  let(:vendedor) { create(:user, role: "vendedor") }
  let(:caja) { create(:user, role: "caja") }
  let(:product) { create(:product) }
  let(:seller) { create(:user, role: "vendedor", name: "Vendedor Registró") }
  let!(:open_order) do
    o = create(:order, :on_account, user: seller, contact_name: "Juan Pérez", contact_phone: "11 5555 1234",
               total_amount: 1000, original_total_amount: 1000)
    create(:order_item, order: o, product: product, quantity: 1, unit_price: 1000)
    o
  end

  describe "GET index" do
    it "lists open operations for a vendedor" do
      sign_in vendedor
      get web_payments_on_account_index_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Juan Pérez")
      expect(response.body).to include("Vendedor Registró")
    end

    it "filters by contact query" do
      sign_in caja
      get web_payments_on_account_index_path, params: { q: "Juan" }
      expect(response.body).to include("Juan Pérez")
    end

    it "shows the sale total, which a cash discount does not lower" do
      sale = create(:order, :on_account, paper_number: "4647", total_amount: 532_000, original_total_amount: 532_000)
      Payments::CollectOnAccount.call(order: sale, user: caja, discount_percent: 10,
                                      tenders: [ { payment_method: "cash", amount: 250_000 } ])
      sign_in caja

      get web_payments_on_account_index_path

      row = Nokogiri::HTML(response.body).css("tbody tr").find { |tr| tr.text.include?("4647") }
      expect(row.css("td").map { |td| td.text.strip }).to include("$532.000,00", "$250.000,00", "$257.000,00")
    end
  end

  describe "GET show role-based controls" do
    it "shows delivery checkboxes but not the collect button to a vendedor" do
      sign_in vendedor
      get web_payments_on_account_path(open_order)
      expect(response.body).to include("marcar entregado")
      expect(response.body).not_to include("Cobrar →")
      expect(response.body).to include("Vendedor Registró")
    end

    it "shows the collect button but not delivery checkboxes to caja" do
      sign_in caja
      get web_payments_on_account_path(open_order)
      expect(response.body).to include("Cobrar →")
      expect(response.body).not_to include("marcar entregado")
    end

    it "shows the change-product action to a vendedor on undelivered rows only" do
      delivered = create(:order_item, :delivered, order: open_order, product: create(:product),
                         quantity: 1, unit_price: 100)
      sign_in vendedor
      get web_payments_on_account_path(open_order)

      undelivered_path = edit_web_payments_on_account_item_path(open_order, open_order.order_items.first)
      delivered_path   = edit_web_payments_on_account_item_path(open_order, delivered)
      expect(response.body).to include("Cambiar")
      expect(response.body).to include(undelivered_path)
      expect(response.body).not_to include(delivered_path)
    end

    it "hides the change-product action from caja" do
      sign_in caja
      get web_payments_on_account_path(open_order)
      expect(response.body).not_to include("Cambiar")
    end
  end

  describe "GET show collection summary and history" do
    before { sign_in caja }

    it "shows what is left, the earned discount and each collection's discount" do
      note = create(:order, :on_account, customer: Customer.mostrador,
                    total_amount: 1_704_400, original_total_amount: 1_704_400)
      create(:order_item, order: note, product: create(:product), quantity: 1, unit_price: 1_704_400)
      Payments::CollectOnAccount.call(order: note, user: create(:user, :caja), discount_percent: 10,
                                      tenders: [ { payment_method: "cash", amount: 800_000 } ])

      get web_payments_on_account_path(note)

      html = Nokogiri::HTML(response.body)
      summary = html.at_css("[data-summary]").text.squish
      expect(summary).to include("Total de la venta $1.704.400,00", "Pagado $800.000,00",
                                 "Resta pagar $904.400,00", "Descuento ya ganado −$80.000,00",
                                 "Saldo (en digital) $824.400,00", "En efectivo con 10% $733.960,00")
      history = html.at_css("[data-history]").text.squish
      expect(history).to include("$800.000,00", "$80.000,00 · 10%", Date.current.strftime("%d/%m/%Y"))
      expect(response.body).not_to include("Bajó la deuda")
    end

    it "shows an old collection without a recorded discount as received, with no percentage" do
      note = create(:order, :on_account, customer: Customer.mostrador,
                    total_amount: 1000, original_total_amount: 1000)
      create(:order_item, order: note, product: create(:product), quantity: 1, unit_price: 1000)
      payment = create(:payment, customer: note.customer, amount: 400, payment_method: "cash")
      create(:payment_allocation, payment: payment, order: note, amount: 400)

      get web_payments_on_account_path(note)

      history = Nokogiri::HTML(response.body).at_css("[data-history]").text.squish
      expect(history).not_to include("%")
      expect(history.scan("$400,00").size).to eq(1)
      expect(history).to include("—")
      expect(Nokogiri::HTML(response.body).at_css("[data-summary]").text).not_to include("Descuento ya ganado")
    end

    it "shows the overpaid cash and keeps the discount and debt figures right" do
      o = create(:order, :on_account, customer: Customer.mostrador, total_amount: 80_300, original_total_amount: 80_300)
      create(:order_item, order: o, product: create(:product), quantity: 1, unit_price: 80_300)
      Payments::CollectOnAccount.call(order: o, user: create(:user, :caja), discount_percent: 10,
                                      tenders: [ { payment_method: "cash", amount: 72_300 } ],
                                      confirmed_overpaid: 30)

      get web_payments_on_account_path(o)

      summary = Nokogiri::HTML(response.body).at_css("[data-summary]").text
      expect(summary).to include("Cobrado de más")
      expect(summary).to include("+$30,00")
      expect(summary).to include("8.030,00")
      expect(summary).to include("72.300,00")
      history = Nokogiri::HTML(response.body).at_css("[data-history]").text.squish
      expect(history).to include("$72.300,00", "$8.030,00 · 10%")
    end
  end

  describe "history with a voided collection" do
    it "lists the voided collection dimmed and leaves it out of the summary" do
      caja = create(:user, :caja)
      order = create(:order, :on_account, total_amount: 89_000)
      voided = create(:payment, :voided, customer: order.customer, amount: 40_000, payment_date: Date.new(2026, 10, 9))
      create(:voided_payment_allocation, payment: voided, order: order, amount: 40_000, discount_amount: 4_444)
      live = create(:payment, customer: order.customer, amount: 30_000, payment_date: Date.new(2026, 10, 15))
      create(:payment_allocation, payment: live, order: order, amount: 30_000)
      sign_in caja

      get "/web/payments_on_account/#{order.id}"

      rows = Nokogiri::HTML(response.body).css("[data-history] tbody tr")
      expect(rows.size).to eq(2)
      expect(rows.first.text).to include("Anulado", "40.000,00")
      expect(rows.first.at_css("a[href='/web/payments/#{voided.id}']")).to be_present
      expect(Nokogiri::HTML(response.body).at_css("[data-summary]").text).not_to include("40.000")
    end

    it "shows the history to a vendedor without links to the collections" do
      order = create(:order, :on_account, total_amount: 89_000)
      voided = create(:payment, :voided, customer: order.customer, amount: 40_000)
      create(:voided_payment_allocation, payment: voided, order: order, amount: 40_000)
      sign_in vendedor

      get "/web/payments_on_account/#{order.id}"

      expect(response).to have_http_status(:ok)
      history = Nokogiri::HTML(response.body).at_css("[data-history]")
      expect(history.text).to include("Anulado")
      expect(history.at_css("a")).to be_nil
    end
  end

  describe "POST deliver" do
    let!(:location) { create(:stock_location) }

    it "lets a vendedor mark an item delivered" do
      create(:stock_movement, product: product, stock_location: location, quantity: 4, movement_type: "purchase")
      product.recalculate_current_stock!

      sign_in vendedor
      post deliver_web_payments_on_account_path(open_order),
           params: { order_item_ids: [ open_order.order_items.first.id ] }
      expect(response).to redirect_to(web_payments_on_account_path(open_order))
      expect(open_order.order_items.first.reload.delivered_at).to be_present
    end

    it "forbids caja from marking delivery" do
      sign_in caja
      post deliver_web_payments_on_account_path(open_order),
           params: { order_item_ids: [ open_order.order_items.first.id ] }
      expect(open_order.order_items.first.reload.delivered_at).to be_nil
    end

    it "takes the delivered lines off the shelf" do
      create(:stock_movement, product: product, stock_location: location, quantity: 4, movement_type: "purchase")
      product.recalculate_current_stock!
      line = open_order.order_items.first

      sign_in vendedor
      post deliver_web_payments_on_account_path(open_order), params: { order_item_ids: [ line.id ] }

      expect(response).to redirect_to(web_payments_on_account_path(open_order))
      expect(line.reload.delivered_at).to be_present
      expect(product.reload.current_stock).to eq(3)
    end
  end
end
