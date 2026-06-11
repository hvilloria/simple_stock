require "rails_helper"

RSpec.describe Inventory::MarkDelivered do
  let(:order) { create(:order, :on_account, total_amount: 1000, original_total_amount: 1000) }
  let(:item_a) { create(:order_item, order: order, product: create(:product), quantity: 1, unit_price: 500) }
  let(:item_b) { create(:order_item, order: order, product: create(:product), quantity: 1, unit_price: 500) }

  it "marks the given items as delivered" do
    result = described_class.call(order: order, order_item_ids: [ item_a.id ], delivered: true)

    expect(result).to be_success
    expect(item_a.reload.delivered_at).to be_present
    expect(item_b.reload.delivered_at).to be_nil
  end

  it "reverts delivery when delivered: false" do
    item_a.update!(delivered_at: Time.current)
    described_class.call(order: order, order_item_ids: [ item_a.id ], delivered: false)
    expect(item_a.reload.delivered_at).to be_nil
  end

  it "ignores ids that do not belong to the order" do
    other = create(:order_item, order: create(:order, :on_account), product: create(:product), quantity: 1, unit_price: 1)
    result = described_class.call(order: order, order_item_ids: [ other.id ], delivered: true)

    expect(result).to be_success
    expect(other.reload.delivered_at).to be_nil
  end

  it "does not create a StockMovement" do
    expect {
      described_class.call(order: order, order_item_ids: [ item_a.id ], delivered: true)
    }.not_to change(StockMovement, :count)
  end

  it "rejects a non on_account order" do
    immediate = create(:order, order_type: "immediate", total_amount: 100, original_total_amount: 100)
    item = create(:order_item, order: immediate, product: create(:product), quantity: 1, unit_price: 100)
    result = described_class.call(order: immediate, order_item_ids: [ item.id ], delivered: true)
    expect(result).to be_failure
  end
end
