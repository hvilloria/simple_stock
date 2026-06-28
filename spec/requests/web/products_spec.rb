# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Web::Products edit/update", type: :request do
  let(:vendedor) { create(:user, role: "vendedor") }
  let(:admin)    { create(:user, role: "admin") }
  let(:caja)     { create(:user, role: "caja") }
  let(:product)  { create(:product, name: "Disco viejo", brand: "Generic Brand", price_unit: 100) }

  describe "GET /web/products" do
    before { sign_in vendedor }

    it "paginates active products at 20 per page" do
      21.times { |i| create(:product, name: format("Producto %02d", i + 1)) }

      get web_products_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Producto 01")
      expect(response.body).not_to include("Producto 21")

      get web_products_path, params: { page: 2 }
      expect(response.body).to include("Producto 21")
    end

    it "composes search filter with pagination" do
      25.times { |i| create(:product, name: format("Filtro %02d", i + 1), brand: "FRAM") }
      create(:product, name: "Pastilla unica", brand: "Brembo")

      get web_products_path, params: { q: "FRAM" }
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Pastilla unica")
      expect(response.body).to include("Filtro 01")
      expect(response.body).not_to include("Filtro 25")

      get web_products_path, params: { q: "FRAM", page: 2 }
      expect(response.body).to include("Filtro 25")
    end
  end

  describe "GET /web/products/:id/edit" do
    it "permite a un vendedor abrir la edición" do
      sign_in vendedor
      get edit_web_product_path(product)
      expect(response).to have_http_status(:ok)
    end

    it "permite a un admin abrir la edición" do
      sign_in admin
      get edit_web_product_path(product)
      expect(response).to have_http_status(:ok)
    end

    it "redirige a caja (no autorizado)" do
      sign_in caja
      get edit_web_product_path(product)
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "PATCH /web/products/:id" do
    before { sign_in vendedor }

    it "actualiza campos descriptivos y de precio" do
      patch web_product_path(product), params: {
        product: { name: "Disco nuevo", brand: "TRW", origin: "japan", price_unit: "250,50" }
      }

      expect(response).to redirect_to(web_product_path(product))
      follow_redirect!
      product.reload
      expect(product.name).to eq("Disco nuevo")
      expect(product.brand).to eq("TRW")
      expect(product.origin).to eq("japan")
      expect(product.price_unit).to eq(250.50)
    end

    it "no modifica el sku aunque venga en params" do
      original_sku = product.sku
      patch web_product_path(product), params: {
        product: { sku: "HACKED999", name: "Otro nombre" }
      }

      product.reload
      expect(product.sku).to eq(original_sku)
      expect(product.name).to eq("Otro nombre")
    end

    it "re-renderiza edit con 422 cuando es inválido" do
      patch web_product_path(product), params: {
        product: { name: "" }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(product.reload.name).to eq("Disco viejo")
    end

    it "rechaza un cambio de variante que colisiona con otra variante del mismo sku" do
      existing = create(:product, sku: "OEM-123", product_type: "aftermarket", origin: "china", brand: "Marca1")
      target   = create(:product, sku: "OEM-123", product_type: "aftermarket", origin: "japan",  brand: "Marca1")

      patch web_product_path(target), params: {
        product: { origin: "china" }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(target.reload.origin).to eq("japan")
    end
  end
end
