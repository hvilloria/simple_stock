require "rails_helper"

RSpec.describe ComboComponent do
  let(:combo) { create(:product, :combo) }
  let(:part) { create(:product) }

  it "requires a quantity greater than zero" do
    record = described_class.new(combo: combo, product: part, quantity: 0)

    expect(record).not_to be_valid
    expect(record.errors[:quantity]).to be_present
  end

  it "refuses the same product twice in one combo" do
    described_class.create!(combo: combo, product: part, quantity: 1)
    duplicate = described_class.new(combo: combo, product: part, quantity: 2)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:product_id]).to be_present
  end

  it "still resolves a soft-deleted component" do
    record = described_class.create!(combo: combo, product: part, quantity: 1)
    combo.update!(active: false)
    expect(part.destroy).to be_truthy

    expect(record.reload.product).to eq(part)
    expect(part.reload.deleted_at).to be_present
  end
end
