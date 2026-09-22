# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::CancelInvoice do
  let!(:location) { create(:stock_location) }
  let(:supplier)  { create(:supplier) }
  let(:filter)    { create(:product, current_stock: 0) }
  let(:pads)      { create(:product, current_stock: 0) }

  def itemized(items)
    Invoices::CreateInvoice.call(
      supplier: supplier, invoice_number: "FAC-1", amount: nil, currency: "ARS",
      purchase_date: Date.current, due_date: 30.days.from_now, items: items
    ).record
  end

  # Reloaded: the invoice stocked the product through its own instance, so this
  # one still carries the stock it was built with and the removal is refused.
  def adjust(product, quantity)
    Inventory::AdjustStock.call(product: product.reload, stock_location: location,
                                movement_type: "adjustment", quantity: quantity)
  end

  it "flips an amount-only invoice to cancelled and writes no movement" do
    invoice = create(:invoice, :simple_mode, supplier: supplier)

    expect { described_class.call(invoice: invoice) }.not_to change(StockMovement, :count)
    expect(invoice.reload.status).to eq("cancelled")
  end

  it "reverses every unit an itemized invoice added, as an adjustment referencing the invoice" do
    invoice = itemized([ { product_id: filter.id, quantity: 10, unit_cost: 100 },
                         { product_id: pads.id, quantity: 4, unit_cost: 100 } ])

    result = described_class.call(invoice: invoice)

    expect(result.success?).to be true
    expect(filter.reload.current_stock).to eq(0)
    expect(pads.reload.current_stock).to eq(0)
    reversals = invoice.stock_movements.where(movement_type: "adjustment")
    expect(reversals.map(&:quantity)).to contain_exactly(-10, -4)
    expect(invoice.stock_movements.where(movement_type: "purchase").count).to eq(2)
  end

  it "floors the reversal at the stock that is left, and still cancels" do
    invoice = itemized([ { product_id: filter.id, quantity: 10, unit_cost: 100 } ])
    adjust(filter, -7)

    result = described_class.call(invoice: invoice)

    expect(result.success?).to be true
    expect(filter.reload.current_stock).to eq(0)
    expect(invoice.reload.status).to eq("cancelled")
  end

  it "writes no reversal for a product with nothing left" do
    invoice = itemized([ { product_id: filter.id, quantity: 10, unit_cost: 100 } ])
    adjust(filter, -10)

    expect { described_class.call(invoice: invoice) }.not_to change(StockMovement, :count)
    expect(invoice.reload.status).to eq("cancelled")
  end

  it "reverses the same product on two lines once, by the total it added" do
    invoice = itemized([ { product_id: filter.id, quantity: 3, unit_cost: 100 },
                         { product_id: filter.id, quantity: 2, unit_cost: 90 } ])

    described_class.call(invoice: invoice)

    expect(filter.reload.current_stock).to eq(0)
    expect(invoice.stock_movements.where(movement_type: "adjustment").map(&:quantity)).to eq([ -5 ])
  end

  it "refuses an invoice that is not pending" do
    invoice = create(:invoice, :paid, supplier: supplier)

    result = described_class.call(invoice: invoice)

    expect(result.success?).to be false
    expect(result.errors).to include("Solo se pueden cancelar facturas pendientes")
    expect(invoice.reload.status).to eq("paid")
  end

  it "still cancels and reverses when the product was soft-deleted afterwards" do
    invoice = itemized([ { product_id: filter.id, quantity: 10, unit_cost: 100 } ])
    filter.destroy

    result = described_class.call(invoice: invoice)

    expect(result.success?).to be true
    expect(Product.with_deleted.find(filter.id).current_stock).to eq(0)
  end

  it "rolls the status back when a reversal fails" do
    invoice = itemized([ { product_id: filter.id, quantity: 10, unit_cost: 100 } ])
    allow(Inventory::AdjustStock).to receive(:call)
      .and_return(Result.new(success?: false, record: nil, errors: [ "Error adjusting stock" ]))

    result = described_class.call(invoice: invoice)

    expect(result.success?).to be false
    expect(invoice.reload.status).to eq("pending")
  end
end
