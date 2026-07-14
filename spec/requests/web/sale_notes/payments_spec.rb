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

  # Nearest-hundred rounding for discounted cash (Payments::CashRounding).
  # The persisted total_amount is the canonical rounded value, so the allocation
  # closes the balance exactly and the note promotes to `confirmed`.
  describe "POST create — discounted cash rounds to the nearest hundred" do
    def build_note(total, paper:)
      o = create(:order, :pending,
                 order_type: "immediate",
                 paper_number: paper,
                 total_amount: total,
                 original_total_amount: total)
      create(:order_item, order: o, product: product, quantity: 1, unit_price: total, discount_percent: 0)
      o
    end

    it "rounds a tie DOWN (24.500 − 10% = 22.050 → 22.000)" do
      big = build_note(24_500, paper: "G-3001")
      expected = Payments::CashRounding.round_to_nearest_hundred(22_050)
      expect(expected).to eq(22_000)

      post "/web/sale_notes/#{big.id}/payment", params: {
        discount_percent: "10",
        tenders: { "0" => { payment_method: "cash", amount: "22.000,00" } }
      }

      expect(response).to redirect_to(web_sale_notes_path)
      big.reload
      expect(big.total_amount).to eq(expected)
      expect(big.payment_allocations.sum(:amount)).to eq(expected)
      expect(big.outstanding_balance).to eq(0)
      expect(big.status).to eq("confirmed")
    end

    it "rounds UP above the tie (710.775 − 10% = 639.697,5 → 639.700)" do
      big = build_note(710_775, paper: "G-3002")
      expected = Payments::CashRounding.round_to_nearest_hundred(639_697.5)
      expect(expected).to eq(639_700)

      post "/web/sale_notes/#{big.id}/payment", params: {
        discount_percent: "10",
        tenders: { "0" => { payment_method: "cash", amount: "639.700,00" } }
      }

      expect(response).to redirect_to(web_sale_notes_path)
      big.reload
      expect(big.total_amount).to eq(expected)
      expect(big.payment_allocations.sum(:amount)).to eq(expected)
      expect(big.outstanding_balance).to eq(0)
      expect(big.status).to eq("confirmed")
    end
  end

  # Money values POSTed straight at the endpoint, bypassing Stimulus. The backend must
  # normalize correctly or reject — never book a wrong number, never drop the tender.
  describe "POST create — hostile tender amount" do
    def note_for(total, paper:)
      o = create(:order, :pending, order_type: "immediate", paper_number: paper,
                                   total_amount: total, original_total_amount: total)
      create(:order_item, order: o, product: product, quantity: 1, unit_price: total, discount_percent: 0)
      o
    end

    def collect(target, amount)
      post "/web/sale_notes/#{target.id}/payment", params: {
        discount_percent: "0",
        tenders: { "0" => { payment_method: "cash", amount: amount } }
      }
    end

    it "persists 1500000.50 for the Argentine format '1.500.000,50'" do
      target = note_for(BigDecimal("1500000.50"), paper: "H-0001")

      collect(target, "1.500.000,50")

      expect(response).to redirect_to(web_sale_notes_path)
      target.reload
      expect(target.payment_allocations.sum(:amount)).to eq(BigDecimal("1500000.50"))
      expect(target.status).to eq("confirmed")
    end

    it "persists 1500000 for the Argentine thousands '1.500.000'" do
      target = note_for(1_500_000, paper: "H-0002")

      collect(target, "1.500.000")

      expect(response).to redirect_to(web_sale_notes_path)
      target.reload
      expect(target.payment_allocations.sum(:amount)).to eq(1_500_000)
      expect(target.status).to eq("confirmed")
    end

    it "persists 1500.50 for the clean decimal '1500.50'" do
      target = note_for(BigDecimal("1500.50"), paper: "H-0003")

      collect(target, "1500.50")

      expect(response).to redirect_to(web_sale_notes_path)
      target.reload
      expect(target.payment_allocations.sum(:amount)).to eq(BigDecimal("1500.50"))
      expect(target.status).to eq("confirmed")
    end

    it "rejects a non-numeric tender instead of booking zero" do
      expect { collect(note, "abc") }.to change(Payment, :count).by(0)
        .and change(PaymentAllocation, :count).by(0)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(note.reload.status).to eq("pending")
    end

    it "rejects a negative tender" do
      expect { collect(note, "-500") }.to change(Payment, :count).by(0)
        .and change(PaymentAllocation, :count).by(0)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(note.reload.status).to eq("pending")
    end

    it "rejects a blank tender" do
      expect { collect(note, "") }.to change(Payment, :count).by(0)
        .and change(PaymentAllocation, :count).by(0)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(note.reload.status).to eq("pending")
    end
  end
end
