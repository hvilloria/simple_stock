# frozen_string_literal: true

require "rails_helper"

RSpec.describe Inventory::DeductLineStock do
  let!(:location) { create(:stock_location) }
  let(:product)   { create(:product, current_stock: 0) }
  let(:order)     { create(:order, :on_account, total_amount: 100, original_total_amount: 100) }

  def stock!(quantity)
    create(:stock_movement, product: product, stock_location: location, quantity: quantity, movement_type: "purchase")
    product.recalculate_current_stock!
  end

  def line(quantity)
    create(:order_item, order: order, product: product, quantity: quantity, unit_price: 100)
  end

  it "takes the whole line when the shelf covers it" do
    stock!(3)

    result = described_class.call(order_item: line(2), note: "Nota 1")

    expect(result.success?).to be true
    expect(product.reload.current_stock).to eq(1)
    movement = result.record
    expect(movement.movement_type).to eq("sale")
    expect(movement.quantity).to eq(-2)
    expect(movement.reference).to eq(order.order_items.first)
    expect(movement.stock_location).to eq(location)
    expect(movement.note).to eq("Nota 1")
  end

  it "takes only what is there and stops at zero" do
    stock!(3)

    result = described_class.call(order_item: line(5))

    expect(result.success?).to be true
    expect(product.reload.current_stock).to eq(0)
    expect(result.record.quantity).to eq(-3)
  end

  it "writes nothing when the shelf is empty, and still succeeds" do
    result = nil
    expect { result = described_class.call(order_item: line(5)) }.not_to change(StockMovement, :count)

    expect(result.success?).to be true
    expect(result.record).to be_nil
    expect(product.reload.current_stock).to eq(0)
  end

  it "reads the shelf fresh, so two lines of the same product deduct in sequence" do
    stock!(3)
    first  = line(2)
    second = line(2)

    described_class.call(order_item: first)
    described_class.call(order_item: second)

    expect(product.reload.current_stock).to eq(0)
    expect(second.stock_movements.sum(:quantity)).to eq(-1)
  end

  it "fails when there is no stock location" do
    stock!(3)
    item = line(1)
    allow(StockLocation).to receive(:first!).and_raise(ActiveRecord::RecordNotFound)

    result = described_class.call(order_item: item)

    expect(result.success?).to be false
    expect(product.reload.current_stock).to eq(3)
  end
end
