require "rails_helper"

RSpec.describe Payments::CollectOnAccount do
  let(:cashier) { create(:user, :caja) }
  let(:customer) { Customer.mostrador }
  let(:product) { create(:product, price_unit: 100) }
  let(:order) do
    o = create(:order, :on_account,
               customer: customer, total_amount: 1000, original_total_amount: 1000)
    create(:order_item, order: o, product: product, quantity: 10, unit_price: 100)
    o
  end

  describe ".call" do
    let(:note_3738) do
      o = create(:order, :on_account, customer: customer,
                 total_amount: 1_704_400, original_total_amount: 1_704_400)
      create(:order_item, order: o, product: product, quantity: 1, unit_price: 1_704_400)
      o
    end

    def collect(order, amount, discount: 0, method: "cash", confirmed_overpaid: 0)
      described_class.call(user: cashier, order: order, discount_percent: discount,
                           tenders: [ { payment_method: method, amount: amount } ],
                           confirmed_overpaid: confirmed_overpaid)
    end

    it "lowers the debt by the cash received grossed up by the discount, rounded to the peso" do
      result = collect(note_3738, 800_000, discount: 10)

      expect(result).to be_success
      note_3738.reload
      allocation = note_3738.payment_allocations.sole
      expect(allocation.amount).to eq(800_000)
      expect(allocation.discount_amount).to eq(88_889)
      expect(note_3738.total_amount).to eq(1_615_511)
      expect(note_3738.outstanding_balance).to eq(815_511)
      expect(note_3738.payments.sole.amount).to eq(800_000)
    end

    it "rounds what the payment cancels to the peso" do
      collect(note_3738, 100_000, discount: 10)

      expect(note_3738.reload.payment_allocations.sole.discount_amount).to eq(11_111)
      expect(note_3738.outstanding_balance).to eq(1_593_289)
    end

    it "lowers the debt by exactly what was received without a discount" do
      collect(note_3738, 800_000)

      expect(note_3738.reload.outstanding_balance).to eq(904_400)
      expect(note_3738.total_amount).to eq(1_704_400)
      expect(note_3738.payment_allocations.sole.discount_amount).to eq(0)
    end

    # 1.704.400 × 0,90 = 1.533.960, exact.
    it "settles the whole balance with the exact discounted cash" do
      result = collect(note_3738, 1_533_960, discount: 10)

      expect(result).to be_success
      note_3738.reload
      expect(note_3738.outstanding_balance).to eq(0)
      expect(note_3738.status).to eq("confirmed")
      allocation = note_3738.payment_allocations.sole
      expect(allocation.discount_amount).to eq(170_440)
      expect(allocation.overpaid_amount).to eq(0)
    end

    it "settles the balance and records cash above the settle amount as overpaid" do
      result = collect(note_3738, 1_534_000, discount: 10, confirmed_overpaid: 40)

      expect(result).to be_success
      note_3738.reload
      allocation = note_3738.payment_allocations.sole
      expect(allocation.amount).to eq(1_534_000)
      expect(allocation.discount_amount).to eq(170_440)
      expect(allocation.overpaid_amount).to eq(40)
      expect(note_3738.total_amount).to eq(1_534_000)
      expect(note_3738.discounts_total).to eq(170_440)
      expect(note_3738.outstanding_balance).to eq(0)
      expect(note_3738.payments.sole.amount).to eq(1_534_000)
    end

    it "settles a small balance at 10% recording the discount and the overpaid cash" do
      small = create(:order, :on_account, customer: customer, total_amount: 60, original_total_amount: 60)
      create(:order_item, order: small, product: product, quantity: 1, unit_price: 60)

      expect(collect(small, 60, discount: 10, confirmed_overpaid: 6)).to be_success
      small.reload
      expect(small.outstanding_balance).to eq(0)
      expect(small.total_amount).to eq(60)
      expect(small.discounts_total).to eq(6)
      expect(small.payment_allocations.sole.discount_amount).to eq(6)
      expect(small.payment_allocations.sole.overpaid_amount).to eq(6)
    end

    it "refuses a transfer above the balance, naming the amount to settle" do
      result = collect(order, 1_500, method: "bank_transfer")

      expect(result).to be_failure
      expect(result.errors).to eq([ "Es más de lo que debe. Para saldar todo corresponde cobrar $ 1.000,00" ])
      expect(order.reload.outstanding_balance).to eq(1000)
    end

    it "accepts cash above the balance without a discount as overpaid" do
      expect(collect(order, 1_500, confirmed_overpaid: 500)).to be_success
      order.reload
      expect(order.total_amount).to eq(1_500)
      expect(order.overpaid_amount).to eq(500)
      expect(order.outstanding_balance).to eq(0)
    end

    it "records a one-cent cash excess as overpaid" do
      expect(collect(order, 1_000.01, confirmed_overpaid: 0.01)).to be_success
      order.reload
      expect(order.overpaid_amount).to eq(0.01)
      expect(order.outstanding_balance).to eq(0)
    end

    [ nil, 200 ].each do |confirmed|
      it "refuses an overpayment confirmed as #{confirmed.inspect} and writes nothing" do
        result = described_class.call(user: cashier, order: order, discount_percent: 0,
                                      tenders: [ { payment_method: "cash", amount: 1_500 } ],
                                      confirmed_overpaid: confirmed)

        expect(result).to be_failure
        expect(result.errors).to eq([ "El saldo cambió mientras cobrabas. Revisá el monto." ])
        expect(order.reload.total_amount).to eq(1_000)
        expect(order.outstanding_balance).to eq(1_000)
        expect(Payment.count).to eq(0)
        expect(CashMovement.count).to eq(0)
      end
    end

    it "refuses a collection on an operation that is already settled" do
      expect(collect(order, 1_000)).to be_success

      result = collect(order.reload, 1_000, confirmed_overpaid: 1_000)

      expect(result).to be_failure
      expect(result.errors).to eq([ "La operación ya está saldada" ])
      expect(order.reload.total_amount).to eq(1_000)
      expect(Payment.count).to eq(1)
      expect(CashMovement.count).to eq(1)
    end

    it "collects 1 cent short of the balance as a partial without a phantom discount" do
      expect(collect(order, 999.99, method: "bank_transfer")).to be_success
      order.reload
      expect(order.outstanding_balance).to eq(0.01)
      expect(order.total_amount).to eq(1_000)
      expect(order.payment_allocations.sole.discount_amount).to eq(0)
    end

    it "refuses a transfer 1 cent above the balance" do
      result = collect(order, 1_000.01, method: "bank_transfer")

      expect(result).to be_failure
      expect(result.errors).to eq([ "Es más de lo que debe. Para saldar todo corresponde cobrar $ 1.000,00" ])
      expect(order.reload.outstanding_balance).to eq(1000)
    end

    it "refuses an excess the cash part does not cover" do
      result = described_class.call(user: cashier, order: order, discount_percent: 0,
                                    tenders: [ { payment_method: "bank_transfer", amount: 1_100 },
                                               { payment_method: "cash", amount: 50 } ])

      expect(result).to be_failure
      expect(order.reload.outstanding_balance).to eq(1000)
    end

    it "collects a partial cash payment and lowers the balance, staying pending" do
      result = described_class.call(
        user: cashier,
        order: order,
        discount_percent: 0, tenders: [ { payment_method: "cash", amount: 400 } ]
      )

      expect(result).to be_success
      expect(order.reload.outstanding_balance).to eq(600)
      expect(order.status).to eq("pending")
      expect(order.payment_allocations.sum(:amount)).to eq(400)
    end

    it "rejects a discount when any tender is not cash" do
      result = described_class.call(
        user: cashier,
        order: order,
        discount_percent: 10, tenders: [ { payment_method: "bank_transfer", amount: 450 } ]
      )
      expect(result).to be_failure
    end

    it "promotes the order to confirmed when the final payment settles it" do
      described_class.call(user: cashier, order: order,
                           discount_percent: 0, tenders: [ { payment_method: "cash", amount: 600 } ])
      result = described_class.call(user: cashier, order: order.reload,
                                    discount_percent: 0, tenders: [ { payment_method: "cash", amount: 400 } ])

      expect(result).to be_success
      expect(order.reload.outstanding_balance).to eq(0)
      expect(order.status).to eq("confirmed")
    end

    it "splits a collection across methods, one Payment per method" do
      result = described_class.call(
        user: cashier, order: order, discount_percent: 0,
        tenders: [
          { payment_method: "cash", amount: 250 },
          { payment_method: "bank_transfer", amount: 150 }
        ]
      )

      expect(result).to be_success
      expect(order.reload.outstanding_balance).to eq(600)
      expect(order.payment_allocations.sum(:amount)).to eq(400)
      payments = order.payment_allocations.map(&:payment).uniq
      expect(payments.size).to eq(2)
      expect(payments.map(&:payment_method)).to contain_exactly("cash", "bank_transfer")
    end

    # payment_allocations is unique on (payment_id, order_id): two rows of the
    # same method must land in a single allocation, not raise RecordNotUnique.
    it "collapses repeated rows of the same method into one allocation" do
      result = described_class.call(
        user: cashier, order: order, discount_percent: 0,
        tenders: [
          { payment_method: "cash", amount: 250 },
          { payment_method: "cash", amount: 150 }
        ]
      )

      expect(result).to be_success
      expect(order.payment_allocations.count).to eq(1)
      expect(order.payment_allocations.sum(:amount)).to eq(400)
      expect(order.payments.map(&:payment_method)).to eq([ "cash" ])
    end

    it "rejects a non on_account order" do
      immediate = create(:order, :pending, order_type: "immediate",
                         total_amount: 100, original_total_amount: 100)
      result = described_class.call(user: cashier, order: immediate,
                                    discount_percent: 0, tenders: [ { payment_method: "cash", amount: 100 } ])
      expect(result).to be_failure
    end
  end

  describe "cash movements" do
    it "rolls the whole collection back when the cash service fails" do
      allow(Cash::RecordSaleFromPayment).to receive(:call)
        .and_return(Result.new(success?: false, record: nil, errors: [ "Este pago ya fue registrado en caja" ]))

      result = described_class.call(
        user: cashier,
        order: order,
        discount_percent: 0, tenders: [ { payment_method: "cash", amount: 400 } ]
      )

      expect(result).to be_failure
      expect(result.errors.join).to match(/registrado en caja/)
      expect(Payment.count).to eq(0)
      expect(PaymentAllocation.count).to eq(0)
      expect(CashMovement.count).to eq(0)
      expect(order.reload.status).to eq("pending")
      expect(order.outstanding_balance).to eq(1000)
    end

    it "writes a sale movement described from the note and the contact" do
      result = described_class.call(
        user: cashier,
        order: order,
        discount_percent: 0, tenders: [ { payment_method: "bank_transfer", amount: 400 } ]
      )

      expect(result).to be_success
      movement = CashMovement.sole
      expect(movement.category).to eq("sale")
      expect(movement.account).to eq("bank")
      expect(movement.channel).to eq("transfer")
      expect(movement.amount).to eq(400)
      expect(movement.user).to eq(cashier)
      expect(movement.description).to eq("Cobro a cuenta — Nota #{order.paper_number} — Juan Pérez")
      expect(movement.source_payment).to eq(Payment.sole)
    end

    it "writes one movement per arca for a mixed-tender collection" do
      result = described_class.call(
        user: cashier,
        order: order,
        discount_percent: 0,
        tenders: [
          { payment_method: "cash", amount: 250 },
          { payment_method: "bank_card", amount: 150 }
        ]
      )

      expect(result).to be_success
      movements = CashMovement.all
      expect(movements.count).to eq(2)
      expect(movements.map(&:account)).to contain_exactly("drawer", "bank")
      expect(movements.map(&:category).uniq).to eq([ "sale" ])
      expect(movements.map(&:description).uniq.size).to eq(1)
      expect(movements.sum(:amount)).to eq(400)
    end
  end
end
