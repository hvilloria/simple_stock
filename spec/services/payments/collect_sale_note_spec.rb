require "rails_helper"

RSpec.describe Payments::CollectSaleNote do
  let(:cashier) { create(:user, :caja) }
  let(:customer) { Customer.mostrador }
  let!(:stock_location) { create(:stock_location) }
  let(:product) do
    p = create(:product, current_stock: 0, price_unit: 100)
    create(:stock_movement, product: p, stock_location: stock_location, quantity: 50, movement_type: "purchase")
    p.recalculate_current_stock!
    p
  end
  let(:order) do
    o = create(:order, :pending,
               customer: customer, order_type: "immediate",
               paper_number: "CSN-001",
               total_amount: 1000, original_total_amount: 1000)
    create(:order_item, order: o, product: product, quantity: 10, unit_price: 100, discount_percent: 0)
    o
  end

  describe ".call" do
    it "refuses a tender without a payment method and records nothing" do
      result = described_class.call(user: cashier, order: order, discount_percent: 0,
                                    tenders: [ { payment_method: nil, amount: 1000 } ])

      expect(result.failure?).to be true
      expect(result.errors).to eq([ "No se puede guardar el cobro sin medio de pago" ])
      expect(Payment.count).to eq(0)
      expect(order.reload).to be_pending_status
    end

    it "creates payment + allocation and promotes order to confirmed when paid exactly" do
      result = described_class.call(
        user: cashier,
        order: order,
        discount_percent: 0,
        tenders: [ { payment_method: "cash", amount: 1000 } ]
      )

      expect(result).to be_success
      expect(order.reload.status).to eq("confirmed")
      expect(order.payment_allocations.count).to eq(1)
      expect(order.payment_allocations.first.amount).to eq(1000)
      expect(order.payment_allocations.first.payment.payment_method).to eq("cash")
    end

    context "with a 10% cash discount on 80.300" do
      let(:note) do
        o = create(:order, :pending, customer: customer, order_type: "immediate",
                   paper_number: "CSN-100", total_amount: 80_300, original_total_amount: 80_300)
        create(:order_item, order: o, product: product, quantity: 1, unit_price: 80_300, discount_percent: 0)
        o
      end

      def collect(amount, confirmed_overpaid: 0)
        described_class.call(user: cashier, order: note, discount_percent: 10,
                             tenders: [ { payment_method: "cash", amount: amount } ],
                             confirmed_overpaid: confirmed_overpaid)
      end

      it "charges the exact discounted total, without rounding" do
        expect(collect(72_270)).to be_success
        note.reload
        expect(note.total_amount).to eq(72_270)
        expect(note.outstanding_balance).to eq(0)
        expect(note.overpaid_amount).to eq(0)
      end

      it "adds cash collected above the total to the sale and records it as overpaid" do
        expect(collect(72_300, confirmed_overpaid: 30)).to be_success
        note.reload
        expect(note.total_amount).to eq(72_300)
        expect(note.original_total_amount).to eq(80_300)
        expect(note.discount_amount).to eq(8_030)
        expect(note.overpaid_amount).to eq(30)
        note.order_items.each { |oi| expect(oi.discount_percent).to eq(10) }
        expect(note.outstanding_balance).to eq(0)
        expect(note.status).to eq("confirmed")
        expect(note.payments.sole.amount).to eq(72_300)
        expect(CashMovement.find_by(source_payment_id: note.payments.sole.id).amount).to eq(72_300)
      end

      it "accepts the total rounded down to the hundred and closes the note at what was charged" do
        expect(collect(72_200)).to be_success
        note.reload
        expect(note.total_amount).to eq(72_200)
        expect(note.discount_amount).to eq(8_030)
        expect(note.rounding_amount).to eq(-70)
        expect(note.overpaid_amount).to eq(0)
        expect(note.outstanding_balance).to eq(0)
        expect(note.status).to eq("confirmed")
        expect(CashMovement.find_by(source_payment_id: note.payments.sole.id).amount).to eq(72_200)
      end

      it "accepts any amount between the rounded and the exact total" do
        expect(collect(72_250)).to be_success
        expect(note.reload.total_amount).to eq(72_250)
        expect(note.outstanding_balance).to eq(0)
      end

      it "refuses less than the total rounded down to the hundred" do
        expect(collect(72_190)).to be_failure
        expect(note.reload.status).to eq("pending")
      end
    end

    it "accepts cash above the total without a discount" do
      result = described_class.call(user: cashier, order: order, discount_percent: 0,
                                    tenders: [ { payment_method: "cash", amount: 1_050 } ],
                                    confirmed_overpaid: 50)

      expect(result).to be_success
      expect(order.reload.total_amount).to eq(1_050)
      expect(order.overpaid_amount).to eq(50)
    end

    it "records a one-cent excess as overpaid" do
      result = described_class.call(user: cashier, order: order, discount_percent: 0,
                                    tenders: [ { payment_method: "cash", amount: 1_000.01 } ],
                                    confirmed_overpaid: 0.01)

      expect(result).to be_success
      expect(order.reload.total_amount).to eq(BigDecimal("1000.01"))
      expect(order.overpaid_amount).to eq(BigDecimal("0.01"))
    end

    it "puts the excess on the cash allocation of a mixed collection" do
      result = described_class.call(user: cashier, order: order, discount_percent: 0,
                                    tenders: [ { payment_method: "bank_transfer", amount: 600 },
                                               { payment_method: "cash", amount: 450 } ],
                                    confirmed_overpaid: 50)

      expect(result).to be_success
      cash = order.reload.payment_allocations.joins(:payment).find_by(payments: { payment_method: "cash" })
      expect(cash.overpaid_amount).to eq(50)
      expect(order.total_amount).to eq(1_050)
    end

    it "refuses an excess the cash does not cover" do
      result = described_class.call(user: cashier, order: order, discount_percent: 0,
                                    tenders: [ { payment_method: "bank_transfer", amount: 1_000 },
                                               { payment_method: "cash", amount: 0.5 },
                                               { payment_method: "mercado_pago", amount: 100 } ])

      expect(result).to be_failure
      expect(result.errors).to eq([ "Lo cobrado de más solo puede ser en efectivo" ])
      expect(order.reload.status).to eq("pending")
    end

    [ nil, 20 ].each do |confirmed|
      it "refuses an overpayment confirmed as #{confirmed.inspect} and writes nothing" do
        result = described_class.call(user: cashier, order: order, discount_percent: 0,
                                      tenders: [ { payment_method: "cash", amount: 1_050 } ],
                                      confirmed_overpaid: confirmed)

        expect(result).to be_failure
        expect(result.errors).to eq([ "El saldo cambió mientras cobrabas. Revisá el monto." ])
        expect(order.reload.status).to eq("pending")
        expect(order.total_amount).to eq(1_000)
        expect(Payment.count).to eq(0)
        expect(CashMovement.count).to eq(0)
      end
    end

    it "ignores confirmed_overpaid when nothing is collected above the total" do
      result = described_class.call(user: cashier, order: order, discount_percent: 0,
                                    tenders: [ { payment_method: "cash", amount: 1_000 } ],
                                    confirmed_overpaid: 30)

      expect(result).to be_success
      expect(order.reload.overpaid_amount).to eq(0)
    end

    it "rejects discount when any tender is non-cash" do
      result = described_class.call(
        user: cashier,
        order: order,
        discount_percent: 5,
        tenders: [
          { payment_method: "cash", amount: 500 },
          { payment_method: "bank_transfer", amount: 450 }
        ]
      )

      expect(result).to be_failure
      expect(result.errors.join).to match(/efectivo/i)
      expect(order.reload.status).to eq("pending")
    end

    it "rejects discount when cash tender total != new total" do
      result = described_class.call(
        user: cashier,
        order: order,
        discount_percent: 5,
        tenders: [ { payment_method: "cash", amount: 800 } ]
      )

      expect(result).to be_failure
    end

    it "does not round down without a discount" do
      result = described_class.call(user: cashier, order: order, discount_percent: 0,
                                    tenders: [ { payment_method: "cash", amount: 900 } ])

      expect(result).to be_failure
      expect(order.reload.status).to eq("pending")
    end

    it "rejects when tender sum != effective total (no discount)" do
      result = described_class.call(
        user: cashier,
        order: order,
        discount_percent: 0,
        tenders: [ { payment_method: "cash", amount: 999 } ]
      )

      expect(result).to be_failure
    end

    it "rejects credit orders" do
      credit_customer = create(:customer, :with_credit)
      credit = create(:order, :credit_order, :pending,
                      customer: credit_customer,
                      paper_number: "CSN-002",
                      total_amount: 100, original_total_amount: 100)
      result = described_class.call(
        user: cashier,
        order: credit,
        discount_percent: 0,
        tenders: [ { payment_method: "cash", amount: 100 } ]
      )

      expect(result).to be_failure
    end

    it "rejects already-confirmed orders" do
      order.update_column(:status, "confirmed")
      result = described_class.call(
        user: cashier,
        order: order,
        discount_percent: 0,
        tenders: [ { payment_method: "cash", amount: 1000 } ]
      )

      expect(result).to be_failure
    end

    it "rejects invalid discount values (e.g., 7)" do
      result = described_class.call(
        user: cashier,
        order: order,
        discount_percent: 7,
        tenders: [ { payment_method: "cash", amount: 930 } ]
      )

      expect(result).to be_failure
    end

    it "groups multi-tender mix into one Payment per method (no discount)" do
      result = described_class.call(
        user: cashier,
        order: order,
        discount_percent: 0,
        tenders: [
          { payment_method: "cash", amount: 600 },
          { payment_method: "bank_transfer", amount: 400 }
        ]
      )

      expect(result).to be_success
      payments = order.payment_allocations.map(&:payment).uniq
      expect(payments.size).to eq(2)
      expect(payments.map(&:payment_method)).to contain_exactly("cash", "bank_transfer")
    end

    # payment_allocations is unique on (payment_id, order_id): two rows of the
    # same method must land in a single allocation, not raise RecordNotUnique.
    it "collapses repeated rows of the same method into one allocation" do
      result = described_class.call(
        user: cashier,
        order: order,
        discount_percent: 0,
        tenders: [
          { payment_method: "cash", amount: 600 },
          { payment_method: "cash", amount: 400 }
        ]
      )

      expect(result).to be_success
      expect(order.payment_allocations.count).to eq(1)
      expect(order.payment_allocations.sum(:amount)).to eq(1000)
      expect(order.payments.map(&:payment_method)).to eq([ "cash" ])
    end
  end

  describe "cash movements" do
    it "rolls the whole collection back when the cash service fails" do
      allow(Cash::RecordSaleFromPayment).to receive(:call)
        .and_return(Result.new(success?: false, record: nil, errors: [ "Este pago ya fue registrado en caja" ]))

      result = described_class.call(
        user: cashier,
        order: order,
        discount_percent: 0,
        tenders: [ { payment_method: "cash", amount: 1000 } ]
      )

      expect(result).to be_failure
      expect(result.errors.join).to match(/registrado en caja/)
      expect(Payment.count).to eq(0)
      expect(PaymentAllocation.count).to eq(0)
      expect(CashMovement.count).to eq(0)
      expect(order.reload.status).to eq("pending")
    end

    it "writes one movement in the right arca for a single-tender collection" do
      result = described_class.call(
        user: cashier,
        order: order,
        discount_percent: 0,
        tenders: [ { payment_method: "cash", amount: 1000 } ]
      )

      expect(result).to be_success
      movement = CashMovement.sole
      expect(movement.account).to eq("drawer")
      expect(movement.channel).to eq("cash")
      expect(movement.category).to eq("sale")
      expect(movement.amount).to eq(1000)
      expect(movement.description).to be_nil
      expect(movement.user).to eq(cashier)
      expect(movement.source_payment).to eq(order.payment_allocations.first.payment)
    end

    it "writes two movements, one per arca, for a mixed cash + card collection" do
      result = described_class.call(
        user: cashier,
        order: order,
        discount_percent: 0,
        tenders: [
          { payment_method: "cash", amount: 600 },
          { payment_method: "bank_card", amount: 400 }
        ]
      )

      expect(result).to be_success
      movements = CashMovement.order(:amount)
      expect(movements.count).to eq(2)
      expect(movements.map(&:account)).to contain_exactly("drawer", "bank")
      expect(movements.map(&:channel)).to contain_exactly("cash", "card")
      expect(movements.find_by(account: "drawer").amount).to eq(600)
      expect(movements.find_by(account: "bank").amount).to eq(400)
      expect(movements.sum(:amount)).to eq(1000)
    end
  end
end
