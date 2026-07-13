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
  end

  describe "POST deliver" do
    it "lets a vendedor mark an item delivered" do
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
  end
end
