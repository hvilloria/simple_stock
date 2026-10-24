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
      expect(response.body).to include("¿Cuánto se recibe?")
      expect(Nokogiri::HTML(response.body).at_css("input[name='tenders[0][amount]']")["value"]).to be_blank
      expect(response.body).to include("Saldar todo")
      select = Nokogiri::HTML(response.body).at_css("select[name='tenders[0][payment_method]']")
      expect(select.at_css("option[selected]").text).to eq("Seleccionar medio")
    end

    it "hands the form what is left to pay and the discount already earned" do
      sign_in caja
      post web_payments_on_account_payment_path(order),
           params: { discount_percent: "10", tenders: { "0" => { payment_method: "cash", amount: "400" } } }

      get new_web_payments_on_account_payment_path(order)

      form = Nokogiri::HTML(response.body).at_css("[data-controller='on-account-payment']")
      expect(form["data-on-account-payment-remaining-value"].to_d).to eq(600)
      expect(form["data-on-account-payment-earned-value"].to_d).to eq(40)
      expect(form["data-on-account-payment-balance-value"].to_d).to eq(560)
      expect(response.body).not_to include("Debe hoy")
      expect(response.body).not_to include("Baja la deuda en")
    end

    it "opens the discount at 0% on the first collection, without a hint" do
      sign_in caja
      get new_web_payments_on_account_payment_path(order)

      select = Nokogiri::HTML(response.body).at_css("select[name='discount_percent']")
      expect(select.at_css("option[selected]")["value"]).to eq("0")
      expect(response.body).not_to include("El cobro anterior fue con")
    end

    it "preselects the discount of the last collection" do
      sign_in caja
      post web_payments_on_account_payment_path(order),
           params: { discount_percent: "10", tenders: { "0" => { payment_method: "cash", amount: "400" } } }

      get new_web_payments_on_account_payment_path(order)

      select = Nokogiri::HTML(response.body).at_css("select[name='discount_percent']")
      expect(select.at_css("option[selected]")["value"]).to eq("10")
      expect(response.body).to include("El cobro anterior fue con 10%")
    end
  end

  describe "POST create" do
    it "keeps the last collection's discount preselected on a refused collection" do
      sign_in caja
      post web_payments_on_account_payment_path(order),
           params: { discount_percent: "10", tenders: { "0" => { payment_method: "cash", amount: "400" } } }

      post web_payments_on_account_payment_path(order),
           params: { discount_percent: "0", tenders: { "0" => { amount: "100" } } }

      expect(response).to have_http_status(:unprocessable_entity)
      select = Nokogiri::HTML(response.body).at_css("select[name='discount_percent']")
      expect(select.at_css("option[selected]")["value"]).to eq("10")
    end

    it "settles the operation with the discounted cash rounded down to the hundred" do
      big = create(:order, :on_account, total_amount: 100_400, original_total_amount: 100_400)
      create(:order_item, order: big, product: product, quantity: 1, unit_price: 100_400)
      sign_in caja

      post web_payments_on_account_payment_path(big),
           params: { discount_percent: "10", tenders: { "0" => { payment_method: "cash", amount: "90.300,00" } } }

      expect(response).to redirect_to(web_payments_on_account_path(big))
      expect(big.reload.outstanding_balance).to eq(0)
      expect(big.payment_allocations.sole.discount_amount).to eq(10_100)
    end

    it "refuses a tender without a payment method" do
      sign_in caja
      expect {
        post web_payments_on_account_payment_path(order),
             params: { discount_percent: "0", tenders: { "0" => { amount: "400" } } }
      }.not_to change(Payment, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("No se puede guardar el cobro sin medio de pago")
    end

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

    it "takes the cash received and lowers the debt by it plus the discount on it" do
      big = create(:order, :on_account, customer: Customer.mostrador,
                   total_amount: 1_704_400, original_total_amount: 1_704_400)
      create(:order_item, order: big, product: create(:product), quantity: 1, unit_price: 1_704_400)

      sign_in caja
      post web_payments_on_account_payment_path(big),
           params: { discount_percent: "10",
                     tenders: { "0" => { payment_method: "cash", amount: "800.000,00" } } }

      expect(response).to redirect_to(web_payments_on_account_path(big))
      expect(big.reload.outstanding_balance).to eq(824_400)
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

    it "settles with AR-formatted cash above the balance" do
      sign_in caja
      post web_payments_on_account_payment_path(order),
           params: { discount_percent: "0", confirmed_overpaid: "50,00",
                     tenders: { "0" => { payment_method: "cash", amount: "1.050,00" } } }

      expect(response).to redirect_to(web_payments_on_account_path(order))
      expect(order.reload.outstanding_balance).to eq(0)
      expect(order.overpaid_amount).to eq(50)
    end

    it "refuses a repeated settling POST instead of booking it as overpaid" do
      sign_in caja
      params = { discount_percent: "0", confirmed_overpaid: "0",
                 tenders: { "0" => { payment_method: "cash", amount: "1.000,00" } } }
      post web_payments_on_account_payment_path(order), params: params
      expect(response).to redirect_to(web_payments_on_account_path(order))

      expect {
        post web_payments_on_account_payment_path(order), params: params
      }.not_to change(Payment, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("La operación ya está saldada")
      expect(order.reload.total_amount).to eq(1000)
      expect(order.overpaid_amount).to eq(0)
    end

    it "refuses cash above a balance that dropped since the form was loaded" do
      ::Payments::CollectOnAccount.call(user: caja, order: order, discount_percent: 0,
                                        tenders: [ { payment_method: "bank_transfer", amount: 400 } ])
      sign_in caja

      expect {
        post web_payments_on_account_payment_path(order),
             params: { discount_percent: "0", confirmed_overpaid: "0",
                       tenders: { "0" => { payment_method: "cash", amount: "1.000,00" } } }
      }.not_to change(Payment, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("El saldo cambió durante el cobro. Revisar el monto.")
      expect(order.reload.outstanding_balance).to eq(600)
    end

    it "re-renders with the amount to settle when a transfer exceeds what is owed" do
      sign_in caja
      post web_payments_on_account_payment_path(order),
           params: { discount_percent: "0",
                     tenders: { "0" => { payment_method: "bank_transfer", amount: "5000" } } }

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

  describe "note 4647 stored through the collect endpoint" do
    let(:note) do
      o = create(:order, :on_account, customer: Customer.mostrador,
                 total_amount: 532_000, original_total_amount: 532_000)
      create(:order_item, order: o, product: create(:product), quantity: 1, unit_price: 532_000)
      o
    end

    def collect(amount, method: "cash", discount: "10")
      post web_payments_on_account_payment_path(note),
           params: { discount_percent: discount, tenders: { "0" => { payment_method: method, amount: amount } } }
    end

    before do
      sign_in caja
      collect("250.000,00")
    end

    it "stores the first collection with the discount on the cash handed over" do
      payment = Payment.sole
      expect(payment).to have_attributes(payment_method: "cash", amount: 250_000)
      expect(payment.allocations.sole).to have_attributes(amount: 250_000, discount_amount: 25_000,
                                                          covered_amount: 250_000, overpaid_amount: 0)
      expect(note.reload).to have_attributes(total_amount: 507_000, status: "pending", settled_on: nil)
      expect(note.outstanding_balance).to eq(257_000)
      expect(CashMovement.where(source_payment: payment).sole.amount).to eq(250_000)
    end

    it "stores the cash settle" do
      collect("228.800,00")

      settle = Payment.order(:id).last
      expect(settle).to have_attributes(payment_method: "cash", amount: 228_800)
      expect(settle.allocations.sole).to have_attributes(amount: 228_800, discount_amount: 28_200,
                                                         covered_amount: 282_000, overpaid_amount: 0)
      expect(note.reload).to have_attributes(total_amount: 478_800, status: "confirmed",
                                             settled_on: settle.payment_date)
      expect(note.outstanding_balance).to eq(0)
      expect(note.payment_allocations.sum(:amount)).to eq(478_800)
      expect(CashMovement.where(source_payment: note.payments).sum(:amount)).to eq(478_800)
    end

    it "stores the digital settle" do
      collect("257.000,00", method: "bank_transfer", discount: "0")

      settle = Payment.order(:id).last
      expect(settle).to have_attributes(payment_method: "bank_transfer", amount: 257_000)
      expect(settle.allocations.sole).to have_attributes(amount: 257_000, discount_amount: 0,
                                                         covered_amount: 282_000, overpaid_amount: 0)
      expect(note.reload).to have_attributes(total_amount: 507_000, status: "confirmed",
                                             settled_on: settle.payment_date)
      expect(note.outstanding_balance).to eq(0)
      expect(CashMovement.where(source_payment: settle).sole.amount).to eq(257_000)
    end
  end
end
