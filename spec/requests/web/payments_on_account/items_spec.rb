require "rails_helper"

RSpec.describe "Web::PaymentsOnAccount::Items", type: :request do
  let(:vendedor) { create(:user, role: "vendedor") }
  let(:caja) { create(:user, role: "caja") }
  let(:old_product) { create(:product, name: "Bomba importada", price_unit: 500) }
  let(:new_product) { create(:product, name: "Bomba local", price_unit: 300) }
  let(:order) { create(:order, :on_account, total_amount: 1000, original_total_amount: 1000) }
  let!(:item) { create(:order_item, order: order, product: old_product, quantity: 2, unit_price: 500) }

  describe "GET edit" do
    it "renders for a vendedor" do
      sign_in vendedor
      get edit_web_payments_on_account_item_path(order, item)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Cambiar producto")
      expect(response.body).to include("Bomba importada")
    end

    it "redirects caja away" do
      sign_in caja
      get edit_web_payments_on_account_item_path(order, item)
      expect(response).to have_http_status(:redirect)
    end

    it "redirects to the show when the item is already delivered" do
      item.update!(delivered_at: Time.current)
      sign_in vendedor
      get edit_web_payments_on_account_item_path(order, item)

      expect(response).to redirect_to(web_payments_on_account_path(order))
      expect(flash[:alert]).to eq("El producto ya fue entregado")
    end
  end

  describe "PATCH update" do
    it "swaps the product and redirects to the show" do
      sign_in vendedor
      patch web_payments_on_account_item_path(order, item),
            params: { product_id: new_product.id, quantity: 2 }

      expect(response).to redirect_to(web_payments_on_account_path(order))
      item.reload
      expect(item.product).to eq(new_product)
      expect(item.unit_price).to eq(300)
      expect(order.reload.total_amount).to eq(600)
    end

    it "redirects back to edit with an alert on failure" do
      item.update!(delivered_at: Time.current)
      sign_in vendedor
      patch web_payments_on_account_item_path(order, item),
            params: { product_id: new_product.id, quantity: 2 }

      expect(response).to redirect_to(edit_web_payments_on_account_item_path(order, item))
      expect(flash[:alert]).to include("El producto ya fue entregado")
    end

    it "forbids caja" do
      sign_in caja
      patch web_payments_on_account_item_path(order, item),
            params: { product_id: new_product.id, quantity: 2 }

      expect(item.reload.product).to eq(old_product)
    end

    it "rejects a non-numeric quantity" do
      sign_in vendedor
      patch web_payments_on_account_item_path(order, item),
            params: { product_id: new_product.id, quantity: "abc" }

      expect(response).to redirect_to(edit_web_payments_on_account_item_path(order, item))
      expect(flash[:alert]).to include("La cantidad debe ser mayor a cero")
      expect(item.reload.product).to eq(old_product)
      expect(order.reload.total_amount).to eq(1000)
    end

    it "rejects a negative quantity" do
      sign_in vendedor
      patch web_payments_on_account_item_path(order, item),
            params: { product_id: new_product.id, quantity: -3 }

      expect(response).to redirect_to(edit_web_payments_on_account_item_path(order, item))
      expect(flash[:alert]).to include("La cantidad debe ser mayor a cero")
      expect(item.reload.quantity).to eq(2)
      expect(order.reload.total_amount).to eq(1000)
    end

    it "rejects a blank quantity" do
      sign_in vendedor
      patch web_payments_on_account_item_path(order, item),
            params: { product_id: new_product.id, quantity: "" }

      expect(response).to redirect_to(edit_web_payments_on_account_item_path(order, item))
      expect(flash[:alert]).to include("La cantidad debe ser mayor a cero")
      expect(item.reload.quantity).to eq(2)
      expect(order.reload.total_amount).to eq(1000)
    end

    it "rejects an unknown product id" do
      sign_in vendedor
      patch web_payments_on_account_item_path(order, item),
            params: { product_id: -1, quantity: 2 }

      expect(response).to redirect_to(edit_web_payments_on_account_item_path(order, item))
      expect(flash[:alert]).to include("Producto inválido")
      expect(item.reload.product).to eq(old_product)
    end

    it "rejects a product with no catalog price" do
      no_price = create(:product, price_unit: 0)
      sign_in vendedor
      patch web_payments_on_account_item_path(order, item),
            params: { product_id: no_price.id, quantity: 2 }

      expect(response).to redirect_to(edit_web_payments_on_account_item_path(order, item))
      expect(flash[:alert]).to include("no tiene precio de catálogo")
      expect(item.reload.product).to eq(old_product)
    end
  end
end
