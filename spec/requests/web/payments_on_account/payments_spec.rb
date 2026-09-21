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
           params: { amount_to_settle: "400", discount_percent: "0",
                     tenders: { "0" => { payment_method: "cash", amount: "400" } } }

      expect(response).to redirect_to(web_payments_on_account_path(order))
      expect(order.reload.outstanding_balance).to eq(600)

      movement = CashMovement.sole
      expect(movement.user).to eq(caja)
      expect(movement.account).to eq("drawer")
      expect(movement.amount).to eq(400)
      expect(movement.description).to eq("Cobro a cuenta — Nota #{order.paper_number} — #{order.contact_name}")
    end

    it "splits a collection across several payment methods" do
      sign_in caja
      post web_payments_on_account_payment_path(order),
           params: { amount_to_settle: "400", discount_percent: "0",
                     tenders: { "0" => { payment_method: "cash", amount: "250" },
                                "1" => { payment_method: "bank_transfer", amount: "150" } } }

      expect(response).to redirect_to(web_payments_on_account_path(order))
      order.reload
      expect(order.outstanding_balance).to eq(600)
      expect(order.payment_allocations.sum(:amount)).to eq(400)
      expect(order.payments.map(&:payment_method)).to contain_exactly("cash", "bank_transfer")
    end

    it "ignores blank tender rows left behind by the form" do
      sign_in caja
      post web_payments_on_account_payment_path(order),
           params: { amount_to_settle: "400", discount_percent: "0",
                     tenders: { "0" => { payment_method: "cash", amount: "400" },
                                "1" => { payment_method: "bank_transfer", amount: "" } } }

      expect(response).to redirect_to(web_payments_on_account_path(order))
      expect(order.reload.payments.map(&:payment_method)).to eq([ "cash" ])
    end

    it "collects the discounted cash rounded to the nearest hundred" do
      big = create(:order, :on_account, total_amount: 710_775, original_total_amount: 710_775)
      create(:order_item, order: big, product: product, quantity: 1, unit_price: 710_775)

      sign_in caja
      post web_payments_on_account_payment_path(big),
           params: { amount_to_settle: "710775", discount_percent: "10",
                     tenders: { "0" => { payment_method: "cash", amount: "639.700,00" } } }

      expect(response).to redirect_to(web_payments_on_account_path(big))
      big.reload
      expect(big.payment_allocations.sum(:amount)).to eq(639_700) # 639.697,5 → 639.700
      expect(big.total_amount).to eq(639_700)                      # shop absorbs the effective discount
      expect(big.outstanding_balance).to eq(0)
    end

    it "accepts Argentine formatted amounts" do
      sign_in caja
      post web_payments_on_account_payment_path(order),
           params: { amount_to_settle: "1.000,00", discount_percent: "0",
                     tenders: { "0" => { payment_method: "cash", amount: "1.000,00" } } }

      expect(response).to redirect_to(web_payments_on_account_path(order))
      expect(order.reload.outstanding_balance).to eq(0)
    end

    it "rejects a non-numeric tender amount" do
      sign_in caja
      post web_payments_on_account_payment_path(order),
           params: { amount_to_settle: "400", discount_percent: "0",
                     tenders: { "0" => { payment_method: "cash", amount: "abc" } } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(order.reload.outstanding_balance).to eq(1000)
    end

    it "rejects a negative tender amount" do
      sign_in caja
      post web_payments_on_account_payment_path(order),
           params: { amount_to_settle: "400", discount_percent: "0",
                     tenders: { "0" => { payment_method: "cash", amount: "-400" } } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(order.reload.outstanding_balance).to eq(1000)
    end

    it "rejects tenders that do not add up to the cash to collect" do
      sign_in caja
      post web_payments_on_account_payment_path(order),
           params: { amount_to_settle: "400", discount_percent: "0",
                     tenders: { "0" => { payment_method: "cash", amount: "250" },
                                "1" => { payment_method: "bank_transfer", amount: "100" } } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(order.reload.outstanding_balance).to eq(1000)
    end

    it "rejects a discount when a tender is not cash" do
      sign_in caja
      post web_payments_on_account_payment_path(order),
           params: { amount_to_settle: "500", discount_percent: "10",
                     tenders: { "0" => { payment_method: "bank_transfer", amount: "450" } } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(order.reload.outstanding_balance).to eq(1000)
    end

    it "re-renders on invalid collection" do
      sign_in caja
      post web_payments_on_account_payment_path(order),
           params: { amount_to_settle: "5000", discount_percent: "0",
                     tenders: { "0" => { payment_method: "cash", amount: "5000" } } }

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "forbids vendedor from collecting" do
      sign_in vendedor
      post web_payments_on_account_payment_path(order),
           params: { amount_to_settle: "400", discount_percent: "0",
                     tenders: { "0" => { payment_method: "cash", amount: "400" } } }
      expect(order.reload.outstanding_balance).to eq(1000)
    end
  end
end
