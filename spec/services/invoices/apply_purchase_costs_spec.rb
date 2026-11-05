# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::ApplyPurchaseCosts do
  let(:product) { create(:product, cost_unit: 8_100, cost_currency: "USD") }

  def invoice_with(*final_costs)
    create(:invoice, :simple_mode, :in_ars).tap do |invoice|
      final_costs.each do |final_cost|
        create(:invoice_item, invoice: invoice, product: product, quantity: 1,
                              unit_cost: final_cost, final_unit_cost: final_cost)
      end
    end
  end

  it "sets the product cost to the line's final cost in pesos and snapshots the previous one" do
    invoice = invoice_with(BigDecimal("9692.10"))

    result = described_class.call(invoice: invoice)

    expect(result.success?).to be true
    expect(product.reload.cost_unit).to eq(BigDecimal("9692.10"))
    expect(product.cost_currency).to eq("ARS")
    item = invoice.invoice_items.reload.first
    expect(item.previous_cost_unit).to eq(8_100)
    expect(item.previous_cost_currency).to eq("USD")
  end

  it "leaves the cost alone and takes no snapshot for a line whose final cost is zero" do
    invoice = invoice_with(BigDecimal("0"))

    described_class.call(invoice: invoice)

    expect(product.reload.cost_unit).to eq(8_100)
    expect(product.cost_currency).to eq("USD")
    item = invoice.invoice_items.reload.first
    expect(item.previous_cost_unit).to be_nil
    expect(item.previous_cost_currency).to be_nil
  end

  it "lets the later line win when the same product appears twice" do
    invoice = invoice_with(BigDecimal("9692.10"), BigDecimal("10345.50"))

    described_class.call(invoice: invoice)

    expect(product.reload.cost_unit).to eq(BigDecimal("10345.50"))
    first, second = invoice.invoice_items.order(:id)
    expect([ first.previous_cost_unit, first.previous_cost_currency ]).to eq([ 8_100, "USD" ])
    expect([ second.previous_cost_unit, second.previous_cost_currency ]).to eq([ BigDecimal("9692.10"), "ARS" ])
  end

  it "fails with the record's errors when the product cannot be saved" do
    invoice = invoice_with(BigDecimal("9692.10"))
    product.update_column(:sku, "")

    result = described_class.call(invoice: invoice)

    expect(result.success?).to be false
    expect(result.errors).not_to be_empty
  end
end
