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

    it "shows the sale total, the discounts, what was paid and the balance, and how far each collection lowered the debt" do
      note = create(:order, :on_account, customer: Customer.mostrador,
                    total_amount: 1_704_400, original_total_amount: 1_704_400)
      create(:order_item, order: note, product: create(:product), quantity: 1, unit_price: 1_704_400)
      Payments::CollectOnAccount.call(order: note, user: create(:user, :caja), discount_percent: 10,
                                      tenders: [ { payment_method: "cash", amount: 800_000 } ])

      get web_payments_on_account_path(note)

      html = Nokogiri::HTML(response.body)
      summary = html.at_css("[data-summary]").text.squish
      expect(summary).to include("Total de la venta $1.704.400,00", "Descuentos −$88.889,00",
                                 "Pagado $800.000,00", "Saldo $815.511,00")
      expect(summary).not_to include("Total acordado")
      history = html.at_css("[data-history]").text.squish
      expect(history).to include("Efectivo · 10%", "$800.000,00", "$888.889,00")
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
      expect(history.scan("$400,00").size).to eq(2)
      expect(Nokogiri::HTML(response.body).at_css("[data-summary]").text).not_to include("Descuentos")
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
