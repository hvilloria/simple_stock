# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Web::StockAdjustments", type: :request do
  let!(:location) { create(:stock_location) }
  let(:admin)     { create(:user, :admin, name: "Hosward") }
  let(:vendedor)  { create(:user, :vendedor) }
  let(:caja)      { create(:user, :caja) }
  let(:filter)    { create(:product, sku: "FIL-0042", name: "Filtro de aceite", current_stock: 0) }

  def stock!(product, quantity)
    create(:stock_movement, product: product, stock_location: location, quantity: quantity, movement_type: "purchase")
    product.recalculate_current_stock!
  end

  def lines_json
    Nokogiri::HTML(response.body).at_css("[data-controller='stock-adjustment-lines']")["data-stock-adjustment-lines-initial-lines-value"]
  end

  describe "GET /web/stock_adjustments/new" do
    it "opens empty for an admin" do
      sign_in admin
      get new_web_stock_adjustment_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Ajuste de stock")
      expect(JSON.parse(lines_json)).to eq([])
    end

    it "opens with the product it was reached from" do
      stock!(filter, 12)
      sign_in admin
      get new_web_stock_adjustment_path(product_id: filter.id)

      line = JSON.parse(lines_json).first
      expect(line).to include("product_id" => filter.id, "sku" => "FIL-0042", "current_stock" => 12, "counted" => "")
    end

    it "keeps vendedor and caja out" do
      [ vendedor, caja ].each do |user|
        sign_in user
        get new_web_stock_adjustment_path

        expect(response).to redirect_to(authenticated_root_path)
        expect(flash[:alert]).to eq("No tenés permiso para realizar esta acción.")
      end
    end
  end

  describe "POST /web/stock_adjustments" do
    let(:params) { { note: "Conteo de fin de mes", lines: { "0" => { product_id: filter.id, counted: "9" } } } }

    before { stock!(filter, 12) }

    it "saves the count and says how many products changed" do
      sign_in admin
      post web_stock_adjustments_path, params: params

      expect(response).to redirect_to(new_web_stock_adjustment_path)
      expect(flash[:notice]).to eq("Ajuste guardado: 1 producto actualizado")
      expect(filter.reload.current_stock).to eq(9)
      expect(StockMovement.last.user).to eq(admin)
    end

    it "pluralizes the notice" do
      plug = create(:product, current_stock: 0)
      sign_in admin
      post web_stock_adjustments_path, params: params.deep_merge(lines: { "1" => { product_id: plug.id, counted: "4" } })

      expect(flash[:notice]).to eq("Ajuste guardado: 2 productos actualizados")
    end

    it "keeps the lines and the reason when the save fails" do
      create(:stock_movement, product: filter, stock_location: location, quantity: -2, movement_type: "sale")
      filter.recalculate_current_stock!
      sign_in admin
      post web_stock_adjustments_path, params: params.deep_merge(lines: { "0" => { counted: "abc" } })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("El stock real de Filtro de aceite debe ser un número entero mayor o igual a 0")
      expect(response.body).to include("Conteo de fin de mes")
      line = JSON.parse(lines_json).first
      expect(line).to include("product_id" => filter.id, "current_stock" => 10, "counted" => "abc")
      expect(filter.reload.current_stock).to eq(10)
    end

    it "answers a malformed submission with a message" do
      sign_in admin
      post web_stock_adjustments_path, params: { note: "Conteo", lines: "garbage" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Agregá al menos un producto")
    end

    it "keeps vendedor and caja out" do
      [ vendedor, caja ].each do |user|
        sign_in user
        post web_stock_adjustments_path, params: params

        expect(response).to redirect_to(authenticated_root_path)
      end
      expect(filter.reload.current_stock).to eq(12)
    end
  end

  describe "sidebar" do
    it "shows the page to an admin only" do
      sign_in admin
      get web_products_path
      expect(response.body).to include(new_web_stock_adjustment_path)

      sign_in vendedor
      get web_products_path
      expect(response.body).not_to include(new_web_stock_adjustment_path)
    end
  end
end
