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

    def collect(order, amount, discount: 0, method: "cash")
      described_class.call(user: cashier, order: order, discount_percent: discount,
                           tenders: [ { payment_method: method, amount: amount } ])
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

    # 1.704.400 × 0,90 = 1.533.960 → nearest hundred 1.534.000.
    it "settles the whole balance when the cash is the amount to settle it all" do
      result = collect(note_3738, 1_534_000, discount: 10)

      expect(result).to be_success
      expect(note_3738.reload.outstanding_balance).to eq(0)
      expect(note_3738.status).to eq("confirmed")
      expect(note_3738.payment_allocations.sole.discount_amount).to eq(170_400)
    end

    it "refuses cash that would cancel more than is owed, naming the amount to settle" do
      result = collect(note_3738, 2_000_000, discount: 10)

      expect(result).to be_failure
      expect(result.errors).to eq([ "Es más de lo que debe. Para saldar todo con 10% corresponde cobrar $ 1.534.000,00" ])
      expect(note_3738.reload.outstanding_balance).to eq(1_704_400)
    end

    it "refuses cash just short of the settle amount whose grossed-up value exceeds the balance" do
      result = collect(note_3738, 1_533_980, discount: 10)

      expect(result).to be_failure
      expect(result.errors.first).to include("$ 1.534.000,00")
    end

    context "when rounding to the hundred would exceed a small balance" do
      let(:small_order) do
        o = create(:order, :on_account, customer: customer,
                   total_amount: 60, original_total_amount: 60)
        create(:order_item, order: o, product: product, quantity: 1, unit_price: 60)
        o
      end

      it "settles the balance without raising the total or storing a negative discount" do
        result = collect(small_order, 60, discount: 10)

        expect(result).to be_success
        small_order.reload
        expect(small_order.outstanding_balance).to eq(0)
        expect(small_order.total_amount).to eq(60)
        expect(small_order.payment_allocations.sole.discount_amount).to eq(0)
      end

      it "names the balance as the amount to settle when more cash is offered" do
        result = collect(small_order, 100, discount: 10)

        expect(result).to be_failure
        expect(result.errors.first).to include("$ 60,00")
      end
    end

    it "refuses more than the balance without a discount" do
      result = collect(order, 1_500)

      expect(result.errors).to eq([ "Es más de lo que debe. Para saldar todo corresponde cobrar $ 1.000,00" ])
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
