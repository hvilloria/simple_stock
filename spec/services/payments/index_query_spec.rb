# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::IndexQuery do
  let(:today) { Date.new(2026, 10, 15) }

  def payment_on(date, method: "cash", amount: 10_000, paper: nil, status: :active, contact: nil)
    order = create(:order, :on_account, paper_number: paper || format("%04d", rand(1000..9999)),
                                        contact_name: contact || "Juan Pérez", total_amount: amount)
    payment = create(:payment, customer: order.customer, payment_date: date, payment_method: method, amount: amount)
    if status == :voided
      create(:voided_payment_allocation, payment: payment, order: order, amount: amount)
      payment.update!(status: "voided", voided_at: Time.current, void_reason: "Monto mal cargado")
    else
      create(:payment_allocation, payment: payment, order: order, amount: amount)
    end
    payment
  end

  def query(**opts)
    described_class.new(from: today, to: today, **opts)
  end

  it "lists active payments of the period, newest first" do
    older = payment_on(today)
    newer = payment_on(today)
    payment_on(today - 1)
    payment_on(today, status: :voided)

    expect(query.relation.to_a).to eq([ newer, older ])
  end

  it "filters by status and method" do
    voided = payment_on(today, status: :voided)
    transfer = payment_on(today, method: "bank_transfer")

    expect(query(status: "voided").relation.to_a).to eq([ voided ])
    expect(query(status: "all").relation.count).to eq(2)
    expect(query(payment_method: "bank_transfer").relation.to_a).to eq([ transfer ])
    expect(query(payment_method: "bitcoin").relation.count).to eq(1)
  end

  it "finds a payment by note or contact across history, voided ones included" do
    old = payment_on(today - 40, paper: "4601", status: :voided)
    payment_on(today, paper: "4700", contact: "Pedro")

    expect(described_class.new(from: nil, to: nil, status: "all", search: "4601").relation.to_a).to eq([ old ])
    expect(described_class.new(from: nil, to: nil, search: "pedro").relation.count).to eq(1)
  end

  it "totals active payments per method only" do
    payment_on(today, amount: 30_000)
    payment_on(today, amount: 12_000, method: "mercado_pago")
    payment_on(today, amount: 99_000, status: :voided)

    expect(query(status: "all").totals_by_method).to eq("cash" => 30_000, "mercado_pago" => 12_000)
  end
end
