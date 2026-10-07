# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Web::Products edit/update", type: :request do
  let(:vendedor) { create(:user, role: "vendedor") }
  let(:admin)    { create(:user, role: "admin") }
  let(:caja)     { create(:user, role: "caja") }
  let(:product)  { create(:product, name: "Disco viejo", brand: "Generic Brand", price_unit: 100) }

  describe "GET /web/products/search" do
    before { sign_in vendedor }

    it "includes each product's channel prices" do
      product.channel_prices.create!(channel: "mercadolibre", price: 15_000)
      get search_web_products_path, params: { q: product.name }

      item = JSON.parse(response.body).find { |p| p["id"] == product.id }
      expect(item["price_unit"].to_f).to eq(100.0)
      expect(item["channel_prices_map"]).to eq("mercadolibre" => 15_000.0)
    end
  end

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

  describe "GET /web/products/:id — stock movements" do
    let!(:location) { create(:stock_location) }

    it "names the sale note behind a sale movement" do
      order = create(:order, :on_account, paper_number: "3340", total_amount: 100, original_total_amount: 100)
      line  = create(:order_item, order: order, product: product, quantity: 1, unit_price: 100)
      create(:stock_movement, :sale, product: product, stock_location: location, reference: line)

      sign_in admin
      get "/web/products/#{product.id}"

      expect(response.body).to include("Nota 3340")
    end

    it "names the admin and the reason behind a stock adjustment" do
      counter = create(:user, :admin, name: "Hosward")
      create(:stock_movement, product: product, stock_location: location, quantity: -3,
                              movement_type: "adjustment", note: "Conteo de fin de mes", user: counter)

      sign_in admin
      get "/web/products/#{product.id}"

      expect(response.body).to include("Hosward · Conteo de fin de mes")
    end

    it "keeps showing the note of an adjustment nobody signed" do
      create(:stock_movement, product: product, stock_location: location, quantity: 1,
                              movement_type: "adjustment", note: "Anulación nota 3301")

      sign_in admin
      get "/web/products/#{product.id}"

      expect(response.body).to include("Anulación nota 3301")
      expect(response.body).not_to include("· Anulación nota 3301")
    end

    it "offers the adjustment page to an admin only" do
      sign_in admin
      get "/web/products/#{product.id}"
      expect(response.body).to include(new_web_stock_adjustment_path(product_id: product.id))

      sign_in vendedor
      get "/web/products/#{product.id}"
      expect(response.body).not_to include(new_web_stock_adjustment_path(product_id: product.id))
    end
  end

  describe "channel prices" do
    before { sign_in vendedor }

    it "saves an AR-formatted ML price on update" do
      patch web_product_path(product), params: { product: { name: product.name },
                                                 channel_prices: { mercadolibre: "15.000,00" } }

      expect(response).to redirect_to(web_product_path(product))
      expect(product.reload.price_for("mercadolibre")).to eq(15_000)
    end

    it "removes the ML price when the field is blank" do
      product.channel_prices.create!(channel: "mercadolibre", price: 15_000)
      patch web_product_path(product), params: { product: { name: product.name },
                                                 channel_prices: { mercadolibre: "" } }

      expect(product.reload.channel_prices).to be_empty
    end

    it "re-renders without saving on a negative or non-numeric ML price" do
      [ "-5", "abc" ].each do |raw|
        patch web_product_path(product), params: { product: { name: "Otro" },
                                                   channel_prices: { mercadolibre: raw } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("Precio Mercado Libre debe ser mayor a 0")
        expect(product.reload.name).to eq("Disco viejo")
      end
    end

    it "creates a product with its ML price" do
      post web_products_path, params: {
        product: { sku: "BUJE-NEW", name: "Buje", brand: "X", product_type: "aftermarket",
                   origin: product.origin, price_unit: "10.000,00", cost_currency: "ARS", active: "1" },
        channel_prices: { mercadolibre: "15.000,00" }
      }

      created = Product.find_by(sku: "BUJE-NEW")
      expect(created.price_unit).to eq(10_000)
      expect(created.price_for("mercadolibre")).to eq(15_000)
    end

    describe "re-rendering after a failed save" do
      def ml_input_value
        Nokogiri::HTML(response.body).at_css("input#channel_prices_mercadolibre")["value"]
      end

      it "echoes a cleaned ML price AR-formatted so a later unformat cannot misread it" do
        patch web_product_path(product), params: { product: { name: "" },
                                                   channel_prices: { mercadolibre: "15000.00" } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(ml_input_value).to eq("15.000,00")
      end

      it "echoes an invalid ML price as typed" do
        patch web_product_path(product), params: { product: { name: "Otro" },
                                                   channel_prices: { mercadolibre: "abc" } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(ml_input_value).to eq("abc")
      end
    end

    it "refuses to create a product on a non-numeric ML price" do
      origin = product.origin
      expect {
        post web_products_path, params: {
          product: { sku: "BUJE-BAD", name: "Buje", brand: "X", product_type: "aftermarket",
                     origin: origin, price_unit: "10.000,00", cost_currency: "ARS", active: "1" },
          channel_prices: { mercadolibre: "abc" }
        }
      }.not_to change(Product, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Precio Mercado Libre debe ser mayor a 0")
    end

    it "shows the ML price on the product page, or the fallback" do
      get web_product_path(product)
      expect(response.body).to include("Precio Mercado Libre")
      expect(response.body).to include("Usa el de mostrador")

      product.channel_prices.create!(channel: "mercadolibre", price: 15_000)
      get web_product_path(product)
      expect(response.body).to include("15.000")
    end

    it "prefills the ML price on the edit form" do
      product.channel_prices.create!(channel: "mercadolibre", price: 15_000)
      get edit_web_product_path(product)
      expect(response.body).to include("15.000,00")
    end
  end
end
