# frozen_string_literal: true

require "rails_helper"

RSpec.describe Inventory::RestoreLineStock do
  let!(:location) { create(:stock_location) }
  let(:product)   { create(:product, current_stock: 0) }
  let(:order)     { create(:order, :on_account, total_amount: 100, original_total_amount: 100) }
  let(:line)      { create(:order_item, order: order, product: product, quantity: 3, unit_price: 100) }

  def stock!(quantity)
    create(:stock_movement, product: product, stock_location: location, quantity: quantity, movement_type: "purchase")
    product.recalculate_current_stock!
  end

  it "puts back what the line took, as an adjustment referencing the line" do
    stock!(3)
    sale = Inventory::DeductLineStock.call(order_item: line).record

    result = described_class.call(order_item: line, note: "Cancelación nota 1")

    expect(result.success?).to be true
    expect(product.reload.current_stock).to eq(3)
    expect(result.record.stock_location).to eq(sale.stock_location)
    expect(result.record.movement_type).to eq("adjustment")
    expect(result.record.quantity).to eq(3)
    expect(result.record.reference).to eq(line)
    expect(result.record.note).to eq("Cancelación nota 1")
    expect(line.stock_movements.sum(:quantity)).to eq(0)
  end

  it "puts back on the location the line's sale movement took from" do
    other = create(:stock_location)
    create(:stock_movement, product: product, stock_location: other, quantity: -3, movement_type: "sale", reference: line)
    product.recalculate_current_stock!

    result = described_class.call(order_item: line)

    expect(result.record.stock_location).to eq(other)
    expect(StockLocation.first!).to eq(location)
  end

  it "puts back the net of a line taken, restored and taken again" do
    stock!(3)
    Inventory::DeductLineStock.call(order_item: line)
    described_class.call(order_item: line)
    Inventory::DeductLineStock.call(order_item: line)

    described_class.call(order_item: line)

    expect(product.reload.current_stock).to eq(3)
    expect(line.stock_movements.sum(:quantity)).to eq(0)
  end

  it "puts back only what the floor let the line take" do
    stock!(1)
    Inventory::DeductLineStock.call(order_item: line)

    described_class.call(order_item: line)

    expect(product.reload.current_stock).to eq(1)
  end

  it "writes nothing for a line that took nothing" do
    result = nil
    expect { result = described_class.call(order_item: line) }.not_to change(StockMovement, :count)

    expect(result.success?).to be true
    expect(result.record).to be_nil
  end

  it "writes nothing for a line whose net is already zero" do
    stock!(3)
    Inventory::DeductLineStock.call(order_item: line)
    described_class.call(order_item: line)

    expect { described_class.call(order_item: line) }.not_to change(StockMovement, :count)
  end
end
