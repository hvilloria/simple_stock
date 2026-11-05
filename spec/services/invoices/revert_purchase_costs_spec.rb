# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::RevertPurchaseCosts do
  let!(:location) { create(:stock_location) }
  let(:supplier)  { create(:supplier) }
  let(:product)   { create(:product, cost_unit: 8_100, cost_currency: "USD", current_stock: 0) }

  # Discount 10 and IVA 21: 8.900 printed is 9.692,10 final, 9.500 is 10.345,50.
  def register(*unit_costs, discount: 10)
    items = unit_costs.map { |unit_cost| { product_id: product.id, quantity: 1, unit_cost: unit_cost } }
    Invoices::CreateInvoice.call(
      supplier: supplier, invoice_number: "FAC-#{SecureRandom.hex(3)}", amount: nil, currency: "ARS",
      purchase_date: Date.current, due_date: 30.days.from_now, items: items,
      discount_percentage: discount, iva_percentage: 21
    ).record
  end

  def cost
    product.reload.then { |reloaded| [ reloaded.cost_unit, reloaded.cost_currency ] }
  end

  it "falls back to the newest other purchase of the product" do
    register("8900")
    newer = register("9500")

    result = described_class.call(invoice: newer)

    expect(result.success?).to be true
    expect(cost).to eq([ BigDecimal("9692.10"), "ARS" ])
  end

  it "restores the snapshot when no other purchase exists" do
    invoice = register("8900")

    described_class.call(invoice: invoice)

    expect(cost).to eq([ 8_100, "USD" ])
  end

  it "ignores purchases on cancelled invoices" do
    invoice = register("8900")
    register("9500").update!(status: "cancelled")
    product.reload.update!(cost_unit: BigDecimal("9692.10"), cost_currency: "ARS")

    described_class.call(invoice: invoice)

    expect(cost).to eq([ 8_100, "USD" ])
  end

  it "restores the pre-invoice cost when the product was on two lines" do
    invoice = register("8900", "9500")
    expect(cost).to eq([ BigDecimal("10345.50"), "ARS" ])

    described_class.call(invoice: invoice)

    expect(cost).to eq([ 8_100, "USD" ])
  end

  it "keeps a cost an admin typed after the purchase" do
    invoice = register("8900")
    product.reload.update!(cost_unit: 12_000)

    described_class.call(invoice: invoice)

    expect(cost).to eq([ 12_000, "ARS" ])
  end

  it "keeps the cost a newer purchase set" do
    older = register("8900")
    register("9500")

    described_class.call(invoice: older)

    expect(cost).to eq([ BigDecimal("10345.50"), "ARS" ])
  end

  it "keeps a cost with the same number in another currency" do
    invoice = register("8900")
    product.reload.update!(cost_currency: "USD")

    described_class.call(invoice: invoice)

    expect(cost).to eq([ BigDecimal("9692.10"), "USD" ])
  end

  it "does not touch the cost for an invoice whose lines cost nothing" do
    invoice = register("8900", discount: 100)
    product.reload.update!(cost_unit: 0, cost_currency: "ARS")

    described_class.call(invoice: invoice)

    expect(cost).to eq([ 0, "ARS" ])
  end

  it "leaves the cost alone for a line that carries no snapshot" do
    invoice = register("8900")
    invoice.invoice_items.update_all(previous_cost_unit: nil, previous_cost_currency: nil)

    described_class.call(invoice: invoice)

    expect(cost).to eq([ BigDecimal("9692.10"), "ARS" ])
  end
end
