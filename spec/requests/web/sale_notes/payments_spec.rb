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

    it "offers an empty default option so an untouched selector means NULL" do
      get "/web/sale_notes/#{note.id}/payment/new"
      expect(response.body).to include('<option selected="selected" value="">Sin definir</option>')
      expect(response.body).to include('<option value="none">Sin factura</option>')
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

      movement = CashMovement.sole
      expect(movement.user).to eq(cashier)
      expect(movement.account).to eq("drawer")
      expect(movement.amount).to eq(200)
    end

    it "assigns the invoice type and number chosen by the cashier" do
      post "/web/sale_notes/#{note.id}/payment", params: {
        discount_percent: "0",
        invoice_type: "b",
        invoice_number: "B-00042",
        tenders: { "0" => { payment_method: "cash", amount: "200,00" } }
      }
      expect(response).to redirect_to(web_sale_notes_path)
      expect(note.reload.invoice_type).to eq("b")
      expect(note.invoice_number).to eq("B-00042")
    end

    it "records a deliberate 'sin factura' as none with no number" do
      post "/web/sale_notes/#{note.id}/payment", params: {
        discount_percent: "0",
        invoice_type: "none",
        invoice_number: "",
        tenders: { "0" => { payment_method: "cash", amount: "200,00" } }
      }
      expect(response).to redirect_to(web_sale_notes_path)
      expect(note.reload.invoice_type).to eq("none")
      expect(note.invoice_number).to be_nil
    end

    it "leaves the invoice type NULL and still collects when the selector is untouched" do
      post "/web/sale_notes/#{note.id}/payment", params: {
        discount_percent: "0",
        invoice_type: "",
        invoice_number: "",
        tenders: { "0" => { payment_method: "cash", amount: "200,00" } }
      }
      expect(response).to redirect_to(web_sale_notes_path)
      expect(note.reload.status).to eq("confirmed")
      expect(note.invoice_type).to be_nil
      expect(note.invoice_number).to be_nil
    end

    it "rejects a Factura A with no number without collecting anything" do
      post "/web/sale_notes/#{note.id}/payment", params: {
        discount_percent: "0",
        invoice_type: "a",
        invoice_number: "",
        tenders: { "0" => { payment_method: "cash", amount: "200,00" } }
      }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(note.reload.status).to eq("pending")
      expect(note.invoice_type).to be_nil
      expect(Payment.count).to eq(0)
      expect(CashMovement.count).to eq(0)
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
