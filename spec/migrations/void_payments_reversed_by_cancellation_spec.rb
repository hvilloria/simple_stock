# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261016120000_void_payments_reversed_by_cancellation")

RSpec.describe VoidPaymentsReversedByCancellation do
  let(:canceller) { create(:user) }
  let(:customer) { create(:customer) }

  def migrate!
    ActiveRecord::Migration.suppress_messages { described_class.new.up }
  end

  def payment_with_cash(amount: 500)
    create(:payment, customer: customer, amount: amount).tap do |payment|
      create(:cash_movement, source_payment: payment, amount: amount)
    end
  end

  it "voids an active payment whose cash was reversed and that covers nothing" do
    payment = payment_with_cash
    reversal = travel_to(1.day.from_now) do
      create(:cash_movement, source_payment: payment, amount: -500, user: canceller)
    end

    migrate!

    expect(payment.reload).to have_attributes(status: "voided", voided_by: canceller, void_reason: "Venta anulada")
    expect(payment.voided_at).to be_within(1.second).of(reversal.created_at)
  end

  it "leaves a payment that still covers a note alone" do
    payment = payment_with_cash
    create(:payment_allocation, payment: payment, order: create(:order, customer: customer, total_amount: 500), amount: 500)
    create(:cash_movement, source_payment: payment, amount: -500)

    migrate!

    expect(payment.reload).to be_active_status
  end

  it "leaves a payment whose cash was never reversed alone" do
    payment = payment_with_cash

    migrate!

    expect(payment.reload).to be_active_status
  end

  it "keeps the reason of a payment already voided" do
    payment = payment_with_cash
    create(:cash_movement, source_payment: payment, amount: -500)
    payment.update!(status: "voided", voided_at: 2.days.ago, voided_by: create(:user), void_reason: "Monto mal cargado")

    migrate!

    expect(payment.reload.void_reason).to eq("Monto mal cargado")
  end
end
