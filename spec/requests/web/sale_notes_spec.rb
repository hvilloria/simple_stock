require "rails_helper"

RSpec.describe "Web::SaleNotes", type: :request do
  let(:cashier) { create(:user, role: "caja") }
  let(:vendor)  { create(:user, role: "vendedor") }
  let!(:stock_location) { create(:stock_location) }
  let(:product) do
    p = create(:product, current_stock: 0, price_unit: 100)
    create(:stock_movement, product: p, stock_location: stock_location, quantity: 50, movement_type: "purchase")
    p.recalculate_current_stock!
    p
  end

  describe "GET /web/sale_notes" do
    it "renders pending immediate orders for cashier" do
      sign_in cashier
      note = create(:order, :pending,
                    order_type: "immediate",
                    paper_number: "F-1000",
                    total_amount: 100,
                    original_total_amount: 100)
      create(:order_item, order: note, product: product, quantity: 1, unit_price: 100, discount_percent: 0)

      get "/web/sale_notes"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("F-1000")
    end

    it "forbids vendor access" do
      sign_in vendor
      get "/web/sale_notes"
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "POST /web/sale_notes/:id/cancel" do
    it "cancels a pending note" do
      sign_in cashier
      note = create(:order, :pending,
                    order_type: "immediate",
                    paper_number: "F-1001",
                    total_amount: 100,
                    original_total_amount: 100)
      create(:order_item, order: note, product: product, quantity: 1, unit_price: 100, discount_percent: 0)

      post "/web/sale_notes/#{note.id}/cancel"
      expect(note.reload.status).to eq("cancelled")
    end
  end
end
