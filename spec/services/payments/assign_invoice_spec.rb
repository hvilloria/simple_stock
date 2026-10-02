# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::AssignInvoice do
  let(:payment) { create(:payment, payment_method: "mercado_pago") }

  def assign(type, number = nil)
    described_class.call(payment: payment, invoice_type: type, invoice_number: number)
  end

  it "records an A or B invoice with its number" do
    result = assign("b", " 1452 ")

    expect(result).to be_success
    expect(payment.reload.invoice_type).to eq("b")
    expect(payment.invoice_number).to eq("1452")
  end

  it "records no invoice and drops any number sent along" do
    result = assign("none", "1452")

    expect(result).to be_success
    expect(payment.reload.invoice_type).to eq("none")
    expect(payment.invoice_number).to be_nil
  end

  it "corrects an invoice already recorded" do
    payment.update!(invoice_type: "b", invoice_number: "1425")

    assign("b", "1452")

    expect(payment.reload.invoice_number).to eq("1452")
  end

  it "refuses A or B without a number and leaves the payment untouched" do
    result = assign("a", "")

    expect(result).to be_failure
    expect(result.errors).to eq([ "El número es obligatorio para Factura A o B" ])
    expect(payment.reload.invoice_type).to be_nil
  end

  it "refuses a missing type" do
    result = assign("", "1452")

    expect(result.errors).to eq([ "Elegí el tipo de factura" ])
  end

  it "refuses an unknown type" do
    result = assign("c", "1452")

    expect(result.errors).to eq([ "Tipo de factura inválido" ])
  end

  it "works when the payment's cash day is already closed" do
    movement = create(:cash_movement, :sealed, source_payment: payment, channel: "mercado_pago",
                      account: "mercado_pago", amount: payment.amount)

    result = assign("b", "1452")

    expect(result).to be_success
    expect(movement.reload).to be_sealed
  end
end
