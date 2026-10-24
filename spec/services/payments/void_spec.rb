# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::Void do
  let(:caja) { create(:user, :caja) }
  let(:day) { Date.new(2026, 10, 15) }

  around { |example| travel_to(day) { example.run } }

  def collect_on_account(order, amount, discount: 0, overpaid: 0, date: day)
    result = Payments::CollectOnAccount.call(order: order, user: caja, discount_percent: discount,
                                             confirmed_overpaid: overpaid, payment_date: date,
                                             tenders: [ { payment_method: "cash", amount: amount } ])
    raise result.errors.to_sentence if result.failure?

    Payment.order(:id).last
  end

  def void(payment, reason: "Monto mal cargado", ids: nil)
    ids ||= Payments::VoidCascade.call(payment: payment).ids
    described_class.call(payment: payment, user: caja, reason: reason, payment_ids: ids)
  end

  describe "on-account operation with cash discounts" do
    let(:order) { create(:order, :on_account, total_amount: 89_000) }

    it "voids the chosen and later collections and gives the whole debt back" do
      first = collect_on_account(order, 40_000, discount: 10)
      second = collect_on_account(order, 40_100, discount: 10)
      expect(order.reload).to have_attributes(total_amount: 80_100, status: "confirmed")

      result = void(first)

      expect(result).to be_success
      expect(result.record).to eq([ second, first ])
      expect(order.reload).to have_attributes(total_amount: 89_000, status: "pending", settled_on: nil)
      expect(order.outstanding_balance).to eq(89_000)
      expect(order.payment_allocations).to be_empty
      expect(order.voided_payment_allocations.pluck(:amount, :discount_amount))
        .to contain_exactly([ 40_000, 4_000 ], [ 40_100, 4_900 ])
      expect([ first.reload, second.reload ]).to all(have_attributes(status: "voided", voided_by: caja,
                                                                     void_reason: "Monto mal cargado"))
    end

    it "keeps the earlier collection and restores only what the voided one took" do
      kept = collect_on_account(order, 40_000, discount: 10)
      voided = collect_on_account(order, 40_100, discount: 10)

      void(voided)

      expect(kept.reload).to be_active_status
      expect(order.reload.total_amount).to eq(89_000 - 4_000)
      expect(order.outstanding_balance).to eq(45_000)
      expect(order.discounts_total).to eq(4_000)
    end

    it "takes the overpaid cash back out of the total" do
      payment = collect_on_account(order, 90_000, overpaid: 1_000)
      expect(order.reload.total_amount).to eq(90_000)

      void(payment)

      expect(order.reload.total_amount).to eq(89_000)
    end

    it "gives the total back when a mixed-tender settling collection is voided from its transfer" do
      mixed = create(:order, :on_account, total_amount: 1_000)
      Payments::CollectOnAccount.call(order: mixed, user: caja, discount_percent: 0, confirmed_overpaid: 100,
                                      tenders: [ { payment_method: "cash", amount: 600 },
                                                 { payment_method: "bank_transfer", amount: 500 } ])
      expect(mixed.reload.total_amount).to eq(1_100)

      void(Payment.find_by!(payment_method: "bank_transfer"))

      expect(mixed.reload.total_amount).to eq(1_000)
      expect(mixed.outstanding_balance).to eq(1_000)
    end

    it "reverses each payment's cash on the day it was collected" do
      collected_on = Date.new(2026, 10, 12)
      payment = collect_on_account(order, 40_000, date: collected_on)

      void(payment)

      reversal = payment.reload.reversal_movement
      expect(reversal).to have_attributes(business_date: collected_on, amount: -40_000,
                                          description: "Anulación del cobro ##{payment.id}: Monto mal cargado")
    end
  end

  it "puts a mixed-method sale note back to pending at its original total" do
    order = create(:order, :pending, total_amount: 114_000)
    create_list(:order_item, 2, order: order, unit_price: 57_000)
    result = Payments::CollectSaleNote.call(order: order, user: caja, tenders: [
      { payment_method: "cash", amount: 64_000 },
      { payment_method: "bank_transfer", amount: 50_000 }
    ])
    raise result.errors.to_sentence if result.failure?
    transfer = Payment.order(:id).last

    expect(void(transfer).record.size).to eq(2)
    expect(order.reload).to have_attributes(status: "pending", total_amount: 114_000)
  end

  it "resets the cash discount of a voided sale note" do
    order = create(:order, :pending, total_amount: 114_000)
    create_list(:order_item, 2, order: order, unit_price: 57_000)
    Payments::CollectSaleNote.call(order: order, user: caja, discount_percent: 10,
                                   tenders: [ { payment_method: "cash", amount: 102_600 } ])
    expect(order.reload.total_amount).to eq(102_600)

    void(Payment.order(:id).last)

    expect(order.reload.total_amount).to eq(114_000)
    expect(order.order_items.map(&:discount_percent)).to all(eq(0))
  end

  it "takes a credit overpayment back out of the note" do
    customer = create(:customer, :with_credit)
    note = create(:order, :credit_order, :pending, customer: customer, total_amount: 30_000)
    result = Payments::AllocatePayment.call(customer: customer, payment_date: day, user: caja, allocations: [
      { order_id: note.id, amount: 31_000, payment_method: "cash", confirmed_overpaid: 1_000 }
    ])
    raise result.errors.to_sentence if result.failure?

    void(result.record.first)

    expect(note.reload).to have_attributes(total_amount: 30_000, status: "pending")
  end

  describe "refusals (nothing is written)" do
    let(:order) { create(:order, :on_account, total_amount: 89_000) }
    let!(:first) { collect_on_account(order, 40_000) }

    def expect_untouched
      expect(first.reload).to be_active_status
      expect(order.reload.payment_allocations.count).to eq(1)
      expect(VoidedPaymentAllocation.count).to eq(0)
      expect(CashMovement.where(source_payment_id: first.id).count).to eq(1)
    end

    it "refuses a blank reason" do
      result = void(first, reason: "   ")

      expect(result.errors).to eq([ "Falta indicar el motivo" ])
      expect_untouched
    end

    it "refuses when a collection landed after the list was shown" do
      shown = Payments::VoidCascade.call(payment: first).ids
      later = collect_on_account(order, 10_000)

      result = void(first, ids: shown)

      expect(result.errors).to eq([ "Los cobros a anular cambiaron. Revisar la lista." ])
      expect(later.reload).to be_active_status
      expect(first.reload).to be_active_status
    end

    it "refuses forged ids" do
      expect(void(first, ids: [ "x", -1 ]).errors).to eq([ "Los cobros a anular cambiaron. Revisar la lista." ])
      expect_untouched
    end

    it "refuses a blocked cascade with its message" do
      create(:daily_closing, business_date: day)

      expect(void(first).errors.first).to include("ese día de caja ya se cerró")
      expect_untouched
    end

    it "refuses a second void of the same payment" do
      void(first)

      expect(void(first.reload, ids: [ first.id ]).errors).to eq([ "Este cobro ya está anulado." ])
    end

    it "rolls everything back when a cash reversal fails" do
      second = collect_on_account(order, 10_000)
      allow(Cash::ReversePayment).to receive(:call).and_call_original
      allow(Cash::ReversePayment).to receive(:call).with(hash_including(payment: first))
        .and_return(Result.new(success?: false, record: nil, errors: [ "Error revirtiendo el cobro en caja" ]))

      result = void(first)

      expect(result.errors).to eq([ "Error revirtiendo el cobro en caja" ])
      expect(second.reload).to be_active_status
      expect(order.reload.payment_allocations.count).to eq(2)
      expect(CashMovement.where(source_payment_id: second.id).count).to eq(1)
    end
  end
end
