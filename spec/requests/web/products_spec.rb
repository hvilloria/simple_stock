# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Web::Products", type: :request do
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

  describe "GET /web/products/:id" do
    it "shows the product detail" do
      sign_in vendedor
      get web_product_path(product)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Disco viejo")
      expect(response.body).to include(product.sku)
    end
  end

  describe "POST /web/products" do
    before { sign_in vendedor }

    let(:base_attributes) do
      {
        sku: "OEM-558",
        name: "Pastilla nueva",
        brand: "TRW",
        product_type: "aftermarket",
        origin: "japan",
        cost_currency: "ARS"
      }
    end

    it "creates the product, normalizing the sku and the Argentine amounts" do
      expect {
        post web_products_path, params: {
          product: {
            sku: "oem-555",
            name: "Pastilla nueva",
            brand: "TRW",
            category: "frenos",
            product_type: "aftermarket",
            origin: "japan",
            price_unit: "1.500,50",
            cost_unit: "900",
            cost_currency: "ARS",
            active: "1"
          }
        }
      }.to change(Product, :count).by(1)

      expect(response).to redirect_to(web_products_path)
      created = Product.find_by(name: "Pastilla nueva")
      expect(created.sku).to eq("OEM-555")
      expect(created.price_unit).to eq(1_500.50)
      expect(created.cost_unit).to eq(900)
      expect(created.origin).to eq("japan")

      follow_redirect!
      expect(response.body).to include("Producto creado exitosamente")
    end

    it "re-renders new with 422 when the name is missing" do
      expect {
        post web_products_path, params: {
          product: { sku: "OEM-556", name: "", cost_currency: "ARS" }
        }
      }.not_to change(Product, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "persists a clean decimal price" do
      post web_products_path, params: {
        product: base_attributes.merge(price_unit: "1500.50", cost_unit: "1.500.000,50")
      }

      created = Product.find_by(name: "Pastilla nueva")
      expect(created.price_unit).to eq(1_500.50)
      expect(created.cost_unit).to eq(1_500_000.50)
    end

    it "allows a blank price and cost" do
      post web_products_path, params: {
        product: base_attributes.merge(price_unit: "", cost_unit: "")
      }

      created = Product.find_by(name: "Pastilla nueva")
      expect(created).to be_present
      expect(created.price_unit).to be_nil
      expect(created.cost_unit).to be_nil
    end

    it "rejects an unparseable price instead of saving it as null" do
      expect {
        post web_products_path, params: {
          product: base_attributes.merge(price_unit: "abc")
        }
      }.not_to change(Product, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "rejects an unparseable cost instead of saving it as null" do
      expect {
        post web_products_path, params: {
          product: base_attributes.merge(cost_unit: "1..5")
        }
      }.not_to change(Product, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "rejects a negative price" do
      expect {
        post web_products_path, params: {
          product: base_attributes.merge(price_unit: "-1.500,50")
        }
      }.not_to change(Product, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "re-renders new with 422 when the variant already exists" do
      create(:product, sku: "OEM-777", product_type: "aftermarket", origin: "china", brand: "Marca1")

      expect {
        post web_products_path, params: {
          product: {
            sku: "OEM-777",
            name: "Duplicada",
            brand: "Marca1",
            product_type: "aftermarket",
            origin: "china",
            cost_currency: "ARS"
          }
        }
      }.not_to change(Product, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "GET /web/products/search" do
    before { sign_in caja }

    it "returns only active products matching the query, as JSON" do
      create(:product, name: "Filtro de aceite", sku: "FIL-001", price_unit: 2_500)
      create(:product, name: "Filtro de aire", sku: "FIL-002")
      create(:product, :inactive, name: "Filtro discontinuado", sku: "FIL-003")
      create(:product, name: "Bujia NGK", sku: "BUJ-001")

      get search_web_products_path, params: { q: "Filtro" }

      expect(response).to have_http_status(:ok)
      results = response.parsed_body
      expect(results.map { |p| p["sku"] }).to contain_exactly("FIL-001", "FIL-002")
      expect(results.first.keys).to include("id", "sku", "name", "price_unit", "current_stock")
    end

    it "caps the result set at 10" do
      12.times { |i| create(:product, name: "Junta #{i}", sku: format("JNT-%02d", i)) }

      get search_web_products_path, params: { q: "Junta" }

      expect(response.parsed_body.size).to eq(10)
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

    it "persiste montos en formato argentino y decimal limpio" do
      patch web_product_path(product), params: {
        product: { price_unit: "1.500.000,50", cost_unit: "1500.50" }
      }

      product.reload
      expect(product.price_unit).to eq(1_500_000.50)
      expect(product.cost_unit).to eq(1_500.50)
    end

    it "rechaza un precio ilegible en vez de anularlo" do
      patch web_product_path(product), params: {
        product: { name: "Disco nuevo", price_unit: "abc" }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      product.reload
      expect(product.price_unit).to eq(100)
      expect(product.name).to eq("Disco viejo")
    end

    it "rechaza un costo ilegible en vez de anularlo" do
      product.update!(cost_unit: 50)

      patch web_product_path(product), params: {
        product: { cost_unit: "12.34.56" }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(product.reload.cost_unit).to eq(50)
    end

    it "rechaza un precio negativo" do
      patch web_product_path(product), params: {
        product: { price_unit: "-1.500,50" }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(product.reload.price_unit).to eq(100)
    end

    it "permite vaciar el precio" do
      patch web_product_path(product), params: {
        product: { price_unit: "" }
      }

      expect(response).to redirect_to(web_product_path(product))
      expect(product.reload.price_unit).to be_nil
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

  describe "DELETE /web/products/:id" do
    let!(:target) { create(:product, name: "Para borrar") }

    it "lets an admin soft-delete the product" do
      sign_in admin
      delete web_product_path(target)

      expect(response).to redirect_to(web_products_path)
      expect(Product.exists?(target.id)).to be(false)          # hidden by default scope
      expect(Product.with_deleted.find(target.id).deleted_at).to be_present
      follow_redirect!
      expect(response.body).to include("eliminado")
    end

    it "forbids a vendedor" do
      sign_in vendedor
      delete web_product_path(target)

      expect(response).to have_http_status(:redirect)
      expect(Product.exists?(target.id)).to be(true)
    end

    it "forbids caja" do
      sign_in caja
      delete web_product_path(target)

      expect(response).to have_http_status(:redirect)
      expect(Product.exists?(target.id)).to be(true)
    end
  end
end
