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
    it "asks for what caja receives, empty, with a shortcut to settle the balance" do
      sign_in caja
      get new_web_payments_on_account_payment_path(order)

      expect(response.body).not_to include("amount_to_settle")
      expect(response.body).to include("¿Cuánto recibís?")
      expect(Nokogiri::HTML(response.body).at_css("input[name='tenders[0][amount]']")["value"]).to be_blank
      expect(response.body).to include("Saldar todo")
    end
  end

  describe "POST create" do
    it "lets caja collect a partial payment" do
      sign_in caja
      post web_payments_on_account_payment_path(order),
           params: { discount_percent: "0",
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
           params: { discount_percent: "0",
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
           params: { discount_percent: "0",
                     tenders: { "0" => { payment_method: "cash", amount: "400" },
                                "1" => { payment_method: "bank_transfer", amount: "" } } }

      expect(response).to redirect_to(web_payments_on_account_path(order))
      expect(order.reload.payments.map(&:payment_method)).to eq([ "cash" ])
    end

    it "takes the cash received and lowers the debt by it grossed up by the discount" do
      big = create(:order, :on_account, customer: Customer.mostrador,
                   total_amount: 1_704_400, original_total_amount: 1_704_400)
      create(:order_item, order: big, product: create(:product), quantity: 1, unit_price: 1_704_400)

      sign_in caja
      post web_payments_on_account_payment_path(big),
           params: { discount_percent: "10",
                     tenders: { "0" => { payment_method: "cash", amount: "800.000,00" } } }

      expect(response).to redirect_to(web_payments_on_account_path(big))
      expect(big.reload.outstanding_balance).to eq(815_511)
      expect(big.payment_allocations.sum(:amount)).to eq(800_000)
    end

    it "accepts Argentine formatted amounts" do
      sign_in caja
      post web_payments_on_account_payment_path(order),
           params: { discount_percent: "0",
                     tenders: { "0" => { payment_method: "cash", amount: "1.000,00" } } }

      expect(response).to redirect_to(web_payments_on_account_path(order))
      expect(order.reload.outstanding_balance).to eq(0)
    end

    it "rejects a non-numeric tender amount" do
      sign_in caja
      post web_payments_on_account_payment_path(order),
           params: { discount_percent: "0",
                     tenders: { "0" => { payment_method: "cash", amount: "abc" } } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(order.reload.outstanding_balance).to eq(1000)
    end

    it "rejects a negative tender amount" do
      sign_in caja
      post web_payments_on_account_payment_path(order),
           params: { discount_percent: "0",
                     tenders: { "0" => { payment_method: "cash", amount: "-400" } } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(order.reload.outstanding_balance).to eq(1000)
    end

    it "rejects a discount when a tender is not cash" do
      sign_in caja
      post web_payments_on_account_payment_path(order),
           params: { discount_percent: "10",
                     tenders: { "0" => { payment_method: "bank_transfer", amount: "450" } } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(order.reload.outstanding_balance).to eq(1000)
    end

    it "re-renders with the amount to settle when the cash exceeds what is owed" do
      sign_in caja
      post web_payments_on_account_payment_path(order),
           params: { discount_percent: "0",
                     tenders: { "0" => { payment_method: "cash", amount: "5000" } } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Es más de lo que debe. Para saldar todo corresponde cobrar $ 1.000,00")
      expect(order.reload.outstanding_balance).to eq(1000)
    end

    it "forbids vendedor from collecting" do
      sign_in vendedor
      post web_payments_on_account_payment_path(order),
           params: { discount_percent: "0",
                     tenders: { "0" => { payment_method: "cash", amount: "400" } } }
      expect(order.reload.outstanding_balance).to eq(1000)
    end
  end
end
