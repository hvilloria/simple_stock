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

  context "with a combo line" do
    let(:a) { create(:product, current_stock: 0) }
    let(:b) { create(:product, current_stock: 0) }
    let(:combo) { create(:product, :combo, components: [ [ a, 1 ], [ b, 4 ] ]) }
    let(:combo_line) do
      create(:order_item, order: order, product: combo, quantity: 2, unit_price: 100).tap do |item|
        item.components.create!(product: a, quantity: 1)
        item.components.create!(product: b, quantity: 4)
      end
    end

    def stock_component!(component, quantity)
      create(:stock_movement, product: component, stock_location: location, quantity: quantity, movement_type: "purchase")
      component.recalculate_current_stock!
    end

    it "puts back on each component what left for it" do
      stock_component!(a, 5)
      stock_component!(b, 5)
      Inventory::DeductLineStock.call(order_item: combo_line)
      expect([ a.reload.current_stock, b.reload.current_stock ]).to eq([ 3, 0 ])

      result = described_class.call(order_item: combo_line, note: "Cancelación nota 7")

      expect(result.success?).to be true
      expect(a.reload.current_stock).to eq(5)
      expect(b.reload.current_stock).to eq(5)
      expect(combo.reload.current_stock).to eq(0)
      expect(combo_line.stock_movements.where(movement_type: "adjustment").order(:product_id).pluck(:product_id, :quantity))
        .to eq([ [ a.id, 2 ], [ b.id, 5 ] ])
    end

    it "restores only the components the line's movements took" do
      stock_component!(a, 5)
      stock_component!(b, 5)
      create(:stock_movement, product: a, stock_location: location, quantity: -2, movement_type: "sale", reference: combo_line)
      a.recalculate_current_stock!

      described_class.call(order_item: combo_line)

      expect(a.reload.current_stock).to eq(5)
      expect(b.reload.current_stock).to eq(5)
      expect(combo_line.stock_movements.where(product: b)).to be_empty
    end
  end
end
