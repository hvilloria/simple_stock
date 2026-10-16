# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::VoidCascade do
  let(:caja) { create(:user, :caja) }
  let(:day) { Date.new(2026, 10, 15) }

  around { |example| travel_to(day) { example.run } }

  def collect_on_account(order, amount, method: "cash", discount: 0, date: day)
    result = Payments::CollectOnAccount.call(order: order, user: caja, discount_percent: discount, payment_date: date,
                                             tenders: [ { payment_method: method, amount: amount } ])
    raise result.errors.to_sentence if result.failure?

    Payment.order(:id).last
  end

  def allocate(customer, rows)
    result = Payments::AllocatePayment.call(customer: customer, payment_date: day, user: caja, allocations: rows)
    raise result.errors.to_sentence if result.failure?

    result.record
  end

  it "takes the later collections on an on-account operation, newest first" do
    order = create(:order, :on_account, total_amount: 89_000)
    first = collect_on_account(order, 20_000)
    second = collect_on_account(order, 30_000)
    third = collect_on_account(order, 10_000)

    cascade = described_class.call(payment: second)

    expect(cascade.payments).to eq([ third, second ])
    expect(cascade.payments).not_to include(first)
    expect(cascade.total).to eq(40_000)
    expect(cascade).not_to be_blocked
  end

  it "takes every payment of a sale note, earlier ones included" do
    order = create(:order, :pending, total_amount: 100_000)
    result = Payments::CollectSaleNote.call(order: order, user: caja, tenders: [
      { payment_method: "cash", amount: 60_000 },
      { payment_method: "bank_transfer", amount: 40_000 }
    ])
    raise result.errors.to_sentence if result.failure?
    cash, transfer = Payment.order(:id).last(2)

    expect(described_class.call(payment: transfer).payments).to eq([ transfer, cash ])
  end

  it "follows a credit payment that covered several notes" do
    customer = create(:customer, :with_credit)
    note_a = create(:order, :credit_order, :pending, customer: customer, total_amount: 30_000)
    note_b = create(:order, :credit_order, :pending, customer: customer, total_amount: 30_000)

    earlier_b = allocate(customer, [ { order_id: note_b.id, amount: 5_000, payment_method: "cash" } ]).first
    chosen = allocate(customer, [ { order_id: note_a.id, amount: 10_000, payment_method: "cash" } ]).first
    shared = allocate(customer, [
      { order_id: note_a.id, amount: 10_000, payment_method: "bank_transfer" },
      { order_id: note_b.id, amount: 10_000, payment_method: "bank_transfer" }
    ]).first
    later_b = allocate(customer, [ { order_id: note_b.id, amount: 5_000, payment_method: "mercado_pago" } ]).first

    cascade = described_class.call(payment: chosen)

    expect(cascade.payments).to eq([ later_b, shared, chosen ])
    expect(cascade.payments).not_to include(earlier_b)
  end

  describe "blocks" do
    it "refuses a payment already voided" do
      payment = create(:payment, :voided)

      expect(described_class.call(payment: payment).block).to eq("Este cobro ya está anulado.")
    end

    it "refuses a payment reversed when its sale was cancelled" do
      order = create(:order, :on_account, total_amount: 50_000)
      payment = collect_on_account(order, 20_000)
      Cash::ReversePayment.call(payment: payment, user: caja)

      expect(described_class.call(payment: payment.reload).block)
        .to eq("No se puede anular: el cobro ##{payment.id} ya se revirtió porque se anuló la venta.")
    end

    it "refuses a payment without a cash movement" do
      order = create(:order, :on_account, total_amount: 50_000)
      payment = create(:payment, customer: order.customer, amount: 20_000)
      create(:payment_allocation, payment: payment, order: order, amount: 20_000)

      expect(described_class.call(payment: payment).block)
        .to eq("No se puede anular: el cobro ##{payment.id} no tiene movimiento de caja.")
    end

    it "refuses when any payment in the cascade is on a closed day" do
      order = create(:order, :on_account, total_amount: 89_000)
      chosen = collect_on_account(order, 40_000, date: Date.new(2026, 10, 12))
      collect_on_account(order, 20_000)
      create(:daily_closing, business_date: Date.new(2026, 10, 12))

      expect(described_class.call(payment: chosen).block)
        .to eq("No se puede anular: el cobro ##{chosen.id} es del 12/10/2026 y ese día de caja ya se cerró.")
    end
  end
end
