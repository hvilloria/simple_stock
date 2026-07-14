require "rails_helper"

RSpec.describe "Web::PaymentsOnAccount::Payments", type: :request do
  let(:caja) { create(:user, role: "caja") }
  let(:vendedor) { create(:user, role: "vendedor") }
  let(:product) { create(:product, price_unit: 100) }
  let!(:order) do
    o = create(:order, :on_account, total_amount: 1000, original_total_amount: 1000)
    create(:order_item, order: o, product: product, quantity: 10, unit_price: 100)
    o
  end

  describe "GET new" do
    it "pre-fills the amount with the outstanding balance so the discount engages immediately" do
      sign_in caja
      get new_web_payments_on_account_payment_path(order)
      expect(response.body).to include('value="1.000,00"')
    end
  end

  describe "POST create" do
    it "lets caja collect a partial payment" do
      sign_in caja
      post web_payments_on_account_payment_path(order),
           params: { amount_to_settle: "400", discount_percent: "0", payment_method: "cash" }

      expect(response).to redirect_to(web_payments_on_account_path(order))
      expect(order.reload.outstanding_balance).to eq(600)
    end

    it "derives the cash collected, rounding the discounted cash UP to the next hundred" do
      big = create(:order, :on_account, total_amount: 710_775, original_total_amount: 710_775)
      create(:order_item, order: big, product: product, quantity: 1, unit_price: 710_775)

      sign_in caja
      post web_payments_on_account_payment_path(big),
           params: { amount_to_settle: "710775", discount_percent: "10", payment_method: "cash" }

      expect(response).to redirect_to(web_payments_on_account_path(big))
      big.reload
      expect(big.payment_allocations.sum(:amount)).to eq(639_700) # 639.697,5 → ceil 639.700
      expect(big.total_amount).to eq(639_700)                      # shop absorbs the effective discount
      expect(big.outstanding_balance).to eq(0)
    end

    it "re-renders on invalid collection" do
      sign_in caja
      post web_payments_on_account_payment_path(order),
           params: { amount_to_settle: "5000", discount_percent: "0", payment_method: "cash" }

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "forbids vendedor from collecting" do
      sign_in vendedor
      post web_payments_on_account_payment_path(order),
           params: { amount_to_settle: "400", discount_percent: "0", payment_method: "cash" }
      expect(order.reload.outstanding_balance).to eq(1000)
    end
  end

  # Money values POSTed straight at the endpoint, bypassing Stimulus. The controller derives
  # the cash tender from amount_to_settle, so a mis-parsed value is booked with no invariant
  # to catch it. It must normalize correctly or reject.
  describe "POST create — hostile amount_to_settle" do
    let!(:big) do
      o = create(:order, :on_account, total_amount: 4_000_000, original_total_amount: 4_000_000)
      create(:order_item, order: o, product: product, quantity: 1, unit_price: 4_000_000)
      o
    end

    before { sign_in caja }

    def settle(amount)
      post web_payments_on_account_payment_path(big),
           params: { amount_to_settle: amount, discount_percent: "0", payment_method: "cash" }
    end

    it "persists 1500000.50 for the Argentine format '1.500.000,50'" do
      settle("1.500.000,50")

      expect(response).to redirect_to(web_payments_on_account_path(big))
      expect(big.reload.payment_allocations.sum(:amount)).to eq(BigDecimal("1500000.50"))
    end

    it "persists 1500000 for the Argentine thousands '1.500.000'" do
      settle("1.500.000")

      expect(response).to redirect_to(web_payments_on_account_path(big))
      expect(big.reload.payment_allocations.sum(:amount)).to eq(1_500_000)
    end

    it "persists 1500.50 for the clean decimal '1500.50'" do
      settle("1500.50")

      expect(response).to redirect_to(web_payments_on_account_path(big))
      expect(big.reload.payment_allocations.sum(:amount)).to eq(BigDecimal("1500.50"))
    end

    it "rejects a non-numeric amount instead of booking zero" do
      expect { settle("abc") }.to change(Payment, :count).by(0)
        .and change(PaymentAllocation, :count).by(0)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(big.reload.outstanding_balance).to eq(4_000_000)
    end

    it "rejects a negative amount" do
      expect { settle("-500") }.to change(Payment, :count).by(0)
        .and change(PaymentAllocation, :count).by(0)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(big.reload.outstanding_balance).to eq(4_000_000)
    end

    it "rejects a blank amount" do
      expect { settle("") }.to change(Payment, :count).by(0)
        .and change(PaymentAllocation, :count).by(0)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(big.reload.outstanding_balance).to eq(4_000_000)
    end
  end
end
