require "rails_helper"

RSpec.describe Inventory::MarkDelivered do
  let!(:location) { create(:stock_location) }
  let(:order) { create(:order, :on_account, paper_number: "OA-7", total_amount: 1000, original_total_amount: 1000) }
  let(:product_a) { create(:product, current_stock: 0) }
  let(:product_b) { create(:product, current_stock: 0) }
  let(:item_a) { create(:order_item, order: order, product: product_a, quantity: 2, unit_price: 500) }
  let(:item_b) { create(:order_item, order: order, product: product_b, quantity: 1, unit_price: 500) }

  def stock!(product, quantity)
    create(:stock_movement, product: product, stock_location: location, quantity: quantity, movement_type: "purchase")
    product.recalculate_current_stock!
  end

  before do
    stock!(product_a, 5)
    stock!(product_b, 5)
  end

  it "marks the given items as delivered and takes them off the shelf" do
    result = described_class.call(order: order, order_item_ids: [ item_a.id ], delivered: true)

    expect(result).to be_success
    expect(item_a.reload.delivered_at).to be_present
    expect(item_b.reload.delivered_at).to be_nil
    expect(product_a.reload.current_stock).to eq(3)
    expect(product_b.reload.current_stock).to eq(5)
    expect(item_a.stock_movements.pluck(:quantity, :movement_type, :note)).to eq([ [ -2, "sale", "Entrega nota OA-7" ] ])
  end

  it "takes only what is on the shelf" do
    product_a.stock_movements.destroy_all
    stock!(product_a, 1)

    described_class.call(order: order, order_item_ids: [ item_a.id ], delivered: true)

    expect(item_a.reload.delivered_at).to be_present
    expect(product_a.reload.current_stock).to eq(0)
  end

  it "does nothing twice for a line already delivered" do
    described_class.call(order: order, order_item_ids: [ item_a.id ], delivered: true)

    expect {
      described_class.call(order: order, order_item_ids: [ item_a.id ], delivered: true)
    }.not_to change(StockMovement, :count)
    expect(product_a.reload.current_stock).to eq(3)
  end

  it "reverts delivery when delivered: false and puts the goods back" do
    described_class.call(order: order, order_item_ids: [ item_a.id ], delivered: true)

    result = described_class.call(order: order, order_item_ids: [ item_a.id ], delivered: false)

    expect(result).to be_success
    expect(item_a.reload.delivered_at).to be_nil
    expect(product_a.reload.current_stock).to eq(5)
    expect(item_a.stock_movements.sum(:quantity)).to eq(0)
    expect(item_a.stock_movements.order(:id).last.note).to eq("Entrega deshecha nota OA-7")
  end

  it "leaves an undelivered line alone on delivered: false" do
    expect {
      described_class.call(order: order, order_item_ids: [ item_a.id ], delivered: false)
    }.not_to change(StockMovement, :count)
    expect(item_a.reload.delivered_at).to be_nil
  end

  it "ignores ids that do not belong to the order" do
    other = create(:order_item, order: create(:order, :on_account, total_amount: 1, original_total_amount: 1),
                   product: create(:product), quantity: 1, unit_price: 1)
    result = described_class.call(order: order, order_item_ids: [ other.id ], delivered: true)

    expect(result).to be_success
    expect(other.reload.delivered_at).to be_nil
  end

  it "marks nothing when a movement fails" do
    allow(Inventory::DeductLineStock).to receive(:call)
      .and_return(Result.new(success?: false, record: nil, errors: [ "Error adjusting stock" ]))

    result = described_class.call(order: order, order_item_ids: [ item_a.id, item_b.id ], delivered: true)

    expect(result).to be_failure
    expect(result.errors).to include("Error adjusting stock")
    expect(item_a.reload.delivered_at).to be_nil
    expect(item_b.reload.delivered_at).to be_nil
  end

  it "refuses a cancelled order" do
    order.update!(status: "cancelled")

    result = nil
    expect {
      result = described_class.call(order: order, order_item_ids: [ item_a.id ], delivered: true)
    }.not_to change(StockMovement, :count)

    expect(result).to be_failure
    expect(result.errors).to include("La operación está anulada")
    expect(item_a.reload.delivered_at).to be_nil
    expect(product_a.reload.current_stock).to eq(5)
  end

  it "rejects a non on_account order" do
    immediate = create(:order, order_type: "immediate", total_amount: 100, original_total_amount: 100)
    item = create(:order_item, order: immediate, product: create(:product), quantity: 1, unit_price: 100)
    result = described_class.call(order: immediate, order_item_ids: [ item.id ], delivered: true)
    expect(result).to be_failure
  end
end
