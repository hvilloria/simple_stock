require "rails_helper"

RSpec.describe "Web::SaleNotes::Payments", type: :request do
  let(:cashier) { create(:user, role: "caja") }
  let!(:stock_location) { create(:stock_location) }
  let(:product) do
    p = create(:product, current_stock: 0, price_unit: 100)
    create(:stock_movement, product: p, stock_location: stock_location, quantity: 50, movement_type: "purchase")
    p.recalculate_current_stock!
    p
  end
  let!(:note) do
    o = create(:order, :pending,
               order_type: "immediate",
               paper_number: "G-2000",
               total_amount: 200,
               original_total_amount: 200)
    create(:order_item, order: o, product: product, quantity: 2, unit_price: 100, discount_percent: 0)
    o
  end

  before { sign_in cashier }

  describe "GET new" do
    it "renders the cobro form" do
      get "/web/sale_notes/#{note.id}/payment/new"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("G-2000")
    end
  end

  describe "POST create" do
    it "cobra full cash and confirms the note" do
      post "/web/sale_notes/#{note.id}/payment", params: {
        discount_percent: "0",
        tenders: { "0" => { payment_method: "cash", amount: "200,00" } }
      }
      expect(response).to redirect_to(web_sale_notes_path)
      expect(note.reload.status).to eq("confirmed")
    end

    it "rejects discount with non-cash tender (cash-only rule)" do
      post "/web/sale_notes/#{note.id}/payment", params: {
        discount_percent: "5",
        tenders: {
          "0" => { payment_method: "cash", amount: "100,00" },
          "1" => { payment_method: "bank_transfer", amount: "90,00" }
        }
      }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(note.reload.status).to eq("pending")
    end
  end
end
