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
end
