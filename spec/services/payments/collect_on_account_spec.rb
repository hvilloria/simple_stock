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

    it "refuses a tender without a payment method and records nothing" do
      result = collect(order, 400, method: "")

      expect(result.failure?).to be true
      expect(result.errors).to eq([ "No se puede guardar el cobro sin medio de pago" ])
      expect(Payment.count).to eq(0)
    end

    it "lowers the debt by the cash received plus the discount on it" do
      result = collect(note_3738, 800_000, discount: 10)

      expect(result).to be_success
      note_3738.reload
      allocation = note_3738.payment_allocations.sole
      expect(allocation.amount).to eq(800_000)
      expect(allocation.discount_amount).to eq(80_000)
      expect(allocation.covered_amount).to eq(800_000)
      expect(note_3738.total_amount).to eq(1_624_400)
      expect(note_3738.outstanding_balance).to eq(824_400)
      expect(note_3738.payments.sole.amount).to eq(800_000)
    end

    it "rounds what the payment cancels to the peso" do
      collect(note_3738, 100_000, discount: 10)

      expect(note_3738.reload.payment_allocations.sole.discount_amount).to eq(10_000)
      expect(note_3738.outstanding_balance).to eq(1_594_400)

      twin = create(:order, :on_account, customer: customer,
                    total_amount: 1_704_400, original_total_amount: 1_704_400)
      collect(twin, 12_345, discount: 10)

      expect(twin.reload.payment_allocations.sole.discount_amount).to eq(1_235)
      expect(twin.outstanding_balance).to eq(1_704_400 - 13_580)
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

    it "settles the whole balance with the discounted cash rounded down to the hundred" do
      result = collect(note_3738, 1_533_900, discount: 10)

      expect(result).to be_success
      note_3738.reload
      expect(note_3738.outstanding_balance).to eq(0)
      expect(note_3738.status).to eq("confirmed")
      expect(note_3738.total_amount).to eq(1_533_900)
      allocation = note_3738.payment_allocations.sole
      expect(allocation.discount_amount).to eq(170_500)
      expect(allocation.overpaid_amount).to eq(0)
    end

    it "keeps cash below the rounded hundred as a partial collection" do
      expect(collect(note_3738, 1_533_899, discount: 10)).to be_success

      expect(note_3738.reload.outstanding_balance).to eq(17_111)
      expect(note_3738.status).to eq("pending")
    end

    it "does not round down without a discount" do
      expect(collect(note_3738, 1_704_300)).to be_success

      expect(note_3738.reload.outstanding_balance).to eq(100)
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
        expect(result.errors).to eq([ "El saldo cambió durante el cobro. Revisar el monto." ])
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

    describe "an invoice per tender" do
      def collect_rows(*tenders, discount: 0, target: order)
        described_class.call(user: cashier, order: target, discount_percent: discount, tenders: tenders)
      end

      it "bills each method's payment with its own invoice" do
        result = collect_rows({ payment_method: "cash", amount: 600, invoice_type: "none" },
                              { payment_method: "bank_transfer", amount: 400, invoice_type: "b", invoice_number: "1452" })

        expect(result).to be_success
        payments = order.reload.payments.index_by(&:payment_method)
        expect(payments["cash"]).to have_attributes(invoice_type: "none", invoice_number: nil)
        expect(payments["bank_transfer"]).to have_attributes(invoice_type: "b", invoice_number: "1452")
      end

      it "leaves a payment unbilled when its row has no invoice type" do
        expect(collect_rows({ payment_method: "cash", amount: 400 })).to be_success
        expect(order.reload.payments.sole.invoice_type).to be_nil
      end

      it "ignores a number sent with Sin factura" do
        result = collect_rows({ payment_method: "cash", amount: 300, invoice_type: "none", invoice_number: "99" },
                              { payment_method: "cash", amount: 100, invoice_type: "none" })

        expect(result).to be_success
        expect(order.reload.payments.sole).to have_attributes(amount: 400, invoice_type: "none", invoice_number: nil)
      end

      it "refuses Factura A without a number and records nothing" do
        result = collect_rows({ payment_method: "cash", amount: 300, invoice_type: "none" },
                              { payment_method: "bank_transfer", amount: 200, invoice_type: "a", invoice_number: "  " })

        expect(result).to be_failure
        expect(result.errors).to eq([ "El número es obligatorio para Factura A o B" ])
        expect(order.reload.total_amount).to eq(1000)
        expect(Payment.count).to eq(0)
        expect(PaymentAllocation.where(order: order)).to be_empty
        expect(CashMovement.count).to eq(0)
      end

      it "refuses two rows of one method with different invoices" do
        result = collect_rows({ payment_method: "cash", amount: 300, invoice_type: "b", invoice_number: "1" },
                              { payment_method: "cash", amount: 100, invoice_type: "b", invoice_number: "2" })

        expect(result.errors).to eq([ "Las filas de Efectivo tienen facturas distintas" ])
        expect(order.reload.payments).to be_empty
      end

      it "accepts two rows of one method with the same invoice as one billed payment" do
        result = collect_rows({ payment_method: "cash", amount: 300, invoice_type: "b", invoice_number: "7" },
                              { payment_method: "cash", amount: 100, invoice_type: "b", invoice_number: " 7 " })

        expect(result).to be_success
        expect(order.reload.payments.sole).to have_attributes(amount: 400, invoice_type: "b", invoice_number: "7")
      end

      it "keeps the settle math when the settling cash is billed" do
        collect(order, 400, discount: 10)                       # partial: earns 40, balance 560
        settle = order.reload.cash_settle_amount(10)            # (600 × 0.9) − 40 = 500

        result = collect_rows({ payment_method: "cash", amount: settle, invoice_type: "a", invoice_number: "0001-00000010" },
                              discount: 10)

        expect(result).to be_success
        allocation = order.reload.payment_allocations.order(:id).last
        expect(allocation).to have_attributes(amount: 500, discount_amount: 60, covered_amount: 600)
        expect(order.outstanding_balance).to eq(0)
        expect(allocation.payment).to have_attributes(invoice_type: "a", invoice_number: "0001-00000010")
      end
    end
  end

  describe "note 4647: the discount on the cash handed over" do
    def sale(total)
      o = create(:order, :on_account, customer: customer, total_amount: total, original_total_amount: total)
      create(:order_item, order: o, product: product, quantity: 1, unit_price: total)
      o
    end

    def collect(order, amount, discount: 0, method: "cash", confirmed_overpaid: 0)
      described_class.call(user: cashier, order: order.reload, discount_percent: discount,
                           tenders: [ { payment_method: method, amount: amount } ],
                           confirmed_overpaid: confirmed_overpaid)
    end

    def last_allocation(order)
      order.payment_allocations.order(:id).last
    end

    let(:note_4647) { sale(532_000) }

    it "records note 4647's first collection under the new rule" do
      expect(collect(note_4647, 250_000, discount: 10)).to be_success

      note_4647.reload
      allocation = note_4647.payment_allocations.sole
      expect(allocation.discount_amount).to eq(25_000)
      expect(allocation.covered_amount).to eq(250_000)
      expect(note_4647.total_amount).to eq(507_000)
      expect(note_4647.outstanding_balance).to eq(257_000)
      expect(note_4647.status).to eq("pending")
    end

    context "after the first 250.000 in cash at 10%" do
      before { collect(note_4647, 250_000, discount: 10) }

      it "settles the rest in cash with 10% of what is left" do
        expect(collect(note_4647, 228_800, discount: 10)).to be_success

        note_4647.reload
        allocation = last_allocation(note_4647)
        expect(allocation.discount_amount).to eq(28_200)
        expect(allocation.covered_amount).to eq(282_000)
        expect(note_4647.outstanding_balance).to eq(0)
        expect(note_4647.status).to eq("confirmed")
        expect(note_4647.payments.sum(:amount)).to eq(478_800)
      end

      it "keeps 228.700 as a partial when the settle amount is already a round hundred" do
        expect(collect(note_4647, 228_700, discount: 10)).to be_success

        note_4647.reload
        expect(last_allocation(note_4647).discount_amount).to eq(22_870)
        expect(note_4647.outstanding_balance).to eq(5_430)
        expect(note_4647.status).to eq("pending")
      end

      it "settles the rest by transfer with the digital balance" do
        expect(collect(note_4647, 257_000, method: "bank_transfer")).to be_success

        note_4647.reload
        expect(note_4647.outstanding_balance).to eq(0)
        expect(last_allocation(note_4647).covered_amount).to eq(282_000)
      end

      it "refuses a transfer above the digital balance" do
        result = collect(note_4647, 260_000, method: "bank_transfer")

        expect(result).to be_failure
        expect(result.errors).to eq([ "Es más de lo que debe. Para saldar todo corresponde cobrar $ 257.000,00" ])
      end

      it "books cash above the settle amount as overpaid" do
        expect(collect(note_4647, 230_000, discount: 10, confirmed_overpaid: 1_200)).to be_success

        note_4647.reload
        expect(last_allocation(note_4647)).to have_attributes(overpaid_amount: 1_200, covered_amount: 282_000)
        expect(note_4647.outstanding_balance).to eq(0)
      end

      it "accumulates the earned discount over two partials" do
        expect(collect(note_4647, 100_000, discount: 10)).to be_success

        note_4647.reload
        expect(note_4647.earned_discount).to eq(35_000)
        expect(note_4647.remaining_to_pay).to eq(182_000)
        expect(note_4647.cash_settle_amount(10)).to eq(128_800)
      end

      it "spreads the used-up discount onto one allocation when settling with two methods" do
        result = described_class.call(user: cashier, order: note_4647.reload, discount_percent: 0,
                                      tenders: [ { payment_method: "cash", amount: 157_000 },
                                                 { payment_method: "bank_transfer", amount: 100_000 } ])

        expect(result).to be_success
        note_4647.reload
        expect(note_4647.outstanding_balance).to eq(0)
        new_allocations = note_4647.payment_allocations.order(:id).last(2)
        expect(new_allocations.sum(&:covered_amount)).to eq(282_000)
        cash = new_allocations.find { |a| a.payment.payment_method == "cash" }
        expect(cash.covered_amount).to eq(157_000 + 25_000)
      end

      it "starts from scratch after a settled operation is reopened by an item swap" do
        collect(note_4647, 228_800, discount: 10)
        pricier = create(:product, price_unit: 542_000)

        swap = Sales::ReplaceOrderItem.call(order_item: note_4647.order_items.sole,
                                            product_id: pricier.id, quantity: 1)

        expect(swap).to be_success
        note_4647.reload
        expect(note_4647.remaining_to_pay).to eq(10_000)
        expect(note_4647.earned_discount).to eq(0)
        expect(note_4647.cash_settle_amount(10)).to eq(9_000)
      end

      it "restores remaining, earned discount and cash to settle after a void" do
        collect(note_4647, 100_000, discount: 10)
        second = Payment.order(:id).last

        voided = Payments::Void.call(payment: second, user: cashier, reason: "Monto mal cargado",
                                     payment_ids: Payments::VoidCascade.call(payment: second).ids)

        expect(voided).to be_success
        note_4647.reload
        expect(note_4647.remaining_to_pay).to eq(282_000)
        expect(note_4647.earned_discount).to eq(25_000)
        expect(note_4647.cash_settle_amount(10)).to eq(228_800)
      end
    end

    it "settles with the cash rounded down to the hundred" do
      note = sale(532_050)
      collect(note, 250_000, discount: 10)
      expect(note.reload.cash_settle_amount(10)).to eq(228_845)

      expect(collect(note, 228_800, discount: 10)).to be_success
      expect(note.reload.outstanding_balance).to eq(0)
    end

    it "keeps the whole sale at 95% in cash at 5%" do
      collect(note_4647, 250_000, discount: 5)

      expect(collect(note_4647, note_4647.reload.cash_settle_amount(5), discount: 5)).to be_success
      note_4647.reload
      expect(note_4647.payments.sum(:amount)).to eq(505_400)
      expect(note_4647.outstanding_balance).to eq(0)
    end

    it "finishes a legacy gross-up operation as today" do
      legacy = sale(532_000)
      payment = Payment.create!(customer: customer, amount: 250_000, payment_method: "cash",
                                payment_date: Date.current)
      PaymentAllocation.create!(payment: payment, order: legacy, amount: 250_000, discount_amount: 27_778)
      legacy.update!(total_amount: 504_222)
      expect(legacy.cash_settle_amount(10)).to eq(BigDecimal("228799.80"))

      expect(collect(legacy, 228_700, discount: 10)).to be_success
      expect(legacy.reload.outstanding_balance).to eq(0)
    end

    it "keeps the one-go cash price at 90%" do
      expect(note_4647.cash_settle_amount(10)).to eq(478_800)

      expect(collect(note_4647, 478_800, discount: 10)).to be_success
      expect(note_4647.reload.outstanding_balance).to eq(0)
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
