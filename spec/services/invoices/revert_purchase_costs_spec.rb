# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::RevertPurchaseCosts do
  let!(:location) { create(:stock_location) }
  let(:supplier)  { create(:supplier) }
  let(:product)   { create(:product, cost_unit: 8_100, cost_currency: "USD", current_stock: 0) }

  # Discount 10 and IVA 21: 8.900 printed is 9.692,10 final, 9.500 is 10.345,50, 12.500 is 13.612,50.
  def register(*unit_costs, discount: 10)
    items = unit_costs.map { |unit_cost| { product_id: product.id, quantity: 1, unit_cost: unit_cost } }
    Invoices::CreateInvoice.call(
      supplier: supplier, invoice_number: "FAC-#{SecureRandom.hex(3)}", amount: nil, currency: "ARS",
      purchase_date: Date.current, due_date: 30.days.from_now, items: items,
      discount_percentage: discount, iva_percentage: 21
    ).record
  end

  def cancel(invoice)
    expect(Invoices::CancelInvoice.call(invoice: invoice).success?).to be true
  end

  def cost
    product.reload.then { |reloaded| [ reloaded.cost_unit, reloaded.cost_currency, reloaded.cost_source_invoice_item_id ] }
  end

  def line_of(invoice)
    invoice.invoice_items.order(:id).last
  end

  it "restores the cost the purchase replaced" do
    invoice = register("8900")

    result = described_class.call(invoice: invoice)

    expect(result.success?).to be true
    expect(cost).to eq([ 8_100, "USD", nil ])
  end

  it "goes back to the previous purchase, then to the cost before it" do
    older = register("8900")
    newer = register("9500")

    cancel(newer)
    expect(cost).to eq([ BigDecimal("9692.10"), "ARS", line_of(older).id ])

    cancel(older)
    expect(cost).to eq([ 8_100, "USD", nil ])
  end

  it "keeps the newer purchase's cost, then walks past the cancelled older one" do
    older = register("8900")
    newer = register("9500")

    cancel(older)
    expect(cost).to eq([ BigDecimal("10345.50"), "ARS", line_of(newer).id ])

    cancel(newer)
    expect(cost).to eq([ 8_100, "USD", nil ])
  end

  it "restores a cost typed by hand between two purchases" do
    register("8900")
    product.reload.update!(cost_unit: 150)
    newer = register("9500")

    cancel(newer)

    expect(cost).to eq([ 150, "ARS", nil ])
  end

  it "does not walk past a hand cost equal to a cancelled purchase's cost" do
    cancel(register("8900"))
    product.reload.update!(cost_unit: BigDecimal("9692.10"), cost_currency: "ARS")
    newer = register("9500")

    cancel(newer)

    expect(cost).to eq([ BigDecimal("9692.10"), "ARS", nil ])
  end

  it "restores an empty cost when the product had none before the purchase" do
    product.update!(cost_unit: nil, cost_currency: "ARS")
    invoice = register("8900")

    described_class.call(invoice: invoice)

    expect(cost).to eq([ nil, "ARS", nil ])
  end

  it "restores the pre-invoice cost when the product was on two lines" do
    invoice = register("8900", "9500")
    expect(cost).to eq([ BigDecimal("10345.50"), "ARS", line_of(invoice).id ])

    described_class.call(invoice: invoice)

    expect(cost).to eq([ 8_100, "USD", nil ])
  end

  it "keeps a cost an admin typed after the purchase" do
    invoice = register("8900")
    product.reload.update!(cost_unit: 12_000)

    described_class.call(invoice: invoice)

    expect(cost).to eq([ 12_000, "ARS", nil ])
  end

  it "keeps a cost with the same number moved to another currency" do
    invoice = register("8900")
    product.reload.update!(cost_currency: "USD")

    described_class.call(invoice: invoice)

    expect(cost).to eq([ BigDecimal("9692.10"), "USD", nil ])
  end

  it "does not touch the cost for an invoice whose lines cost nothing" do
    invoice = register("8900", discount: 100)
    product.reload.update!(cost_unit: 0, cost_currency: "ARS")

    described_class.call(invoice: invoice)

    expect(cost).to eq([ 0, "ARS", nil ])
  end

  it "reverts the cost of a product that fails a current validation" do
    invoice = create(:invoice, :simple_mode, :in_ars)
    create(:invoice_item, invoice: invoice, product: product, quantity: 1,
                          unit_cost: BigDecimal("9692.10"), final_unit_cost: BigDecimal("9692.10"))
    Invoices::ApplyPurchaseCosts.call(invoice: invoice)
    product.update_column(:location_code, "bad")

    result = described_class.call(invoice: invoice)

    expect(result.success?).to be true
    expect(cost).to eq([ 8_100, "USD", nil ])
  end

  context "when earlier purchases were cancelled" do
    before { product.update!(cost_unit: 500, cost_currency: "ARS") }

    it "walks back over several cancelled purchases" do
      first = register("8900")
      second = register("9500")
      third = register("12500")

      cancel(first)
      cancel(second)
      cancel(third)

      expect(cost).to eq([ 500, "ARS", nil ])
    end

    it "walks back past cancelled purchases registered in between" do
      first = register("8900")
      second = register("9500")
      cancel(second)
      third = register("12500")
      cancel(first)
      expect(cost).to eq([ BigDecimal("13612.50"), "ARS", line_of(third).id ])

      cancel(third)

      expect(cost).to eq([ 500, "ARS", nil ])
    end

    it "stops at a live purchase behind a cancelled one" do
      first = register("8900")
      second = register("9500")
      third = register("12500")

      cancel(second)
      cancel(third)

      expect(cost).to eq([ BigDecimal("9692.10"), "ARS", line_of(first).id ])
    end

    it "walks back to a cost in another currency" do
      product.update!(cost_unit: 8_100, cost_currency: "USD")
      older = register("8900")
      newer = register("9500")

      cancel(older)
      cancel(newer)

      expect(cost).to eq([ 8_100, "USD", nil ])
    end
  end
end
