# frozen_string_literal: true

require "rails_helper"

RSpec.describe Inventory::AdjustStock do
  let!(:location) { create(:stock_location) }
  let(:product)   { create(:product, current_stock: 0) }
  let(:admin)     { create(:user, :admin) }

  it "records who made the movement" do
    result = described_class.call(product: product, stock_location: location,
                                  movement_type: :adjustment, quantity: 4, note: "Conteo", user: admin)

    expect(result.success?).to be true
    expect(result.record.user).to eq(admin)
    expect(product.reload.current_stock).to eq(4)
  end

  it "leaves the user empty when none is given" do
    result = described_class.call(product: product, stock_location: location,
                                  movement_type: :purchase, quantity: 2)

    expect(result.success?).to be true
    expect(result.record.user).to be_nil
  end

  it "refuses a combo without writing anything" do
    combo = create(:product, :combo)

    result = nil
    expect {
      result = described_class.call(product: combo, stock_location: location,
                                    movement_type: :adjustment, quantity: 2)
    }.not_to change(StockMovement, :count)

    expect(result.failure?).to be true
    expect(result.errors).to eq([ "Un combo no tiene stock propio: ajustar sus piezas" ])
    expect(combo.reload.current_stock).to eq(0)
  end
end
