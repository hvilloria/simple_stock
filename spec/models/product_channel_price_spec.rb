require "rails_helper"

RSpec.describe ProductChannelPrice do
  let(:product) { create(:product, price_unit: 10_000) }

  it "is valid for an own-price channel with a positive price" do
    expect(described_class.new(product: product, channel: "mercadolibre", price: 15_000)).to be_valid
  end

  it "rejects a channel without its own price" do
    record = described_class.new(product: product, channel: "whatsapp", price: 15_000)
    expect(record).not_to be_valid
  end

  it "rejects a zero or negative price with the operator's message" do
    record = described_class.new(product: product, channel: "mercadolibre", price: 0)
    expect(record).not_to be_valid
    expect(record.errors.full_messages).to include("Precio Mercado Libre debe ser mayor a 0")
  end

  it "allows one price per channel and product" do
    described_class.create!(product: product, channel: "mercadolibre", price: 15_000)
    duplicate = described_class.new(product: product, channel: "mercadolibre", price: 16_000)
    expect(duplicate).not_to be_valid
  end

  it "knows which channels have their own price" do
    expect(described_class.own_price?("mercadolibre")).to be true
    expect(described_class.own_price?("counter")).to be false
    expect(described_class.own_price?(nil)).to be false
  end
end
