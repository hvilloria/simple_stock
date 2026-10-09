# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::ChangeMethod do
  let(:date) { Date.new(2026, 10, 1) }
  let(:payment) { create(:payment, payment_method: "cash", amount: 60_000, payment_date: date) }
  let!(:movement) do
    create(:cash_movement, source_payment: payment, business_date: date, amount: 60_000,
                           channel: "cash", account: "drawer")
  end

  def change(method)
    described_class.call(payment: payment, payment_method: method)
  end

  it "moves a cash collection to Mercado Pago, payment and movement alike" do
    result = change("mercado_pago")

    expect(result.success?).to be(true)
    expect(payment.reload.payment_method).to eq("mercado_pago")
    expect(movement.reload).to have_attributes(channel: "mercado_pago", account: "mercado_pago",
                                               amount: 60_000, business_date: date)
  end

  it "lands a bank card in the bank arca" do
    change("bank_card")

    expect(movement.reload).to have_attributes(channel: "card", account: "bank")
  end

  it "lands Mercado Pago moved to cash in the day's drawer" do
    payment.update!(payment_method: "mercado_pago")
    movement.update!(channel: "mercado_pago", account: "mercado_pago")

    change("cash")

    expect(movement.reload).to have_attributes(channel: "cash", account: "drawer")
  end

  it "changes a credit payment covering several orders as a whole" do
    2.times do
      order = create(:order, :credit_order, customer: payment.customer, total_amount: 30_000, original_total_amount: 30_000)
      create(:payment_allocation, payment: payment, order: order, amount: 30_000)
    end

    change("bank_transfer")

    expect(payment.reload.payment_method).to eq("bank_transfer")
    expect(payment.allocations.map(&:amount)).to all(eq(30_000))
    expect(movement.reload).to have_attributes(channel: "transfer", account: "bank")
    expect(CashMovement.where(source_payment_id: payment.id).count).to eq(1)
  end

  it "keeps the collector and the invoice" do
    payment.update!(invoice_type: "b", invoice_number: "1485")
    collector = movement.user

    change("mercado_pago")

    expect(movement.reload.user).to eq(collector)
    expect(payment.reload).to have_attributes(invoice_type: "b", invoice_number: "1485")
  end

  describe "refusals (nothing is written)" do
    def expect_refused(result, message)
      expect(result.failure?).to be(true)
      expect(result.errors).to eq([ message ])
      expect(payment.reload.payment_method).to eq("cash")
      expect(movement.reload).to have_attributes(channel: "cash", account: "drawer")
    end

    it "refuses a blank method" do
      expect_refused(change(""), "No se puede guardar el cobro sin medio de pago")
    end

    it "refuses an unknown method" do
      expect_refused(change("bitcoin"), "Método de pago inválido: bitcoin")
    end

    it "refuses the method it already has" do
      expect_refused(change("cash"), "El cobro ya está registrado con ese medio de pago")
    end

    it "refuses a reversed collection" do
      create(:cash_movement, source_payment: payment, business_date: date, amount: -60_000)

      expect_refused(change("mercado_pago"), "Este cobro fue revertido: no se puede cambiar el medio de pago")
    end

    it "refuses a closed day" do
      create(:daily_closing, business_date: date)

      expect_refused(change("mercado_pago"),
                     "El día 01/10/2026 ya se cerró: el medio de pago no se puede cambiar.")
    end

    it "refuses a cash collection that carried a cash discount" do
      order = create(:order, :on_account, customer: payment.customer, total_amount: 66_667, original_total_amount: 66_667)
      create(:payment_allocation, payment: payment, order: order, amount: 60_000, discount_amount: 6_667)

      expect_refused(change("mercado_pago"), "Este cobro tuvo descuento en efectivo: no se puede pasar a otro medio.")
    end
  end

  it "refuses a collection without a cash movement" do
    bare = create(:payment, payment_method: "cash")

    result = described_class.call(payment: bare, payment_method: "mercado_pago")

    expect(result.errors).to eq([ "Este cobro no tiene movimiento de caja" ])
    expect(bare.reload.payment_method).to eq("cash")
  end
end
