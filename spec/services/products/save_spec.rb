require "rails_helper"

RSpec.describe Products::Save do
  let(:product) { create(:product, price_unit: 10_000) }

  it "saves the product and creates its ML price" do
    result = described_class.call(product: product, attributes: { name: "Buje" },
                                  channel_prices: { "mercadolibre" => 15_000 })

    expect(result).to be_success
    expect(product.reload.name).to eq("Buje")
    expect(product.price_for("mercadolibre")).to eq(15_000)
  end

  it "updates an existing ML price" do
    product.channel_prices.create!(channel: "mercadolibre", price: 15_000)
    described_class.call(product: product, attributes: {}, channel_prices: { "mercadolibre" => 16_000 })
    expect(product.reload.channel_prices.sole.price).to eq(16_000)
  end

  it "removes the ML price when it comes blank" do
    product.channel_prices.create!(channel: "mercadolibre", price: 15_000)
    described_class.call(product: product, attributes: {}, channel_prices: { "mercadolibre" => nil })
    expect(product.reload.channel_prices).to be_empty
    expect(product.price_for("mercadolibre")).to eq(10_000)
  end

  it "saves nothing when the ML price is invalid" do
    result = described_class.call(product: product, attributes: { name: "Nuevo nombre" },
                                  channel_prices: { "mercadolibre" => 0 })

    expect(result).to be_failure
    expect(result.errors).to include("Precio Mercado Libre debe ser mayor a 0")
    expect(product.reload.name).not_to eq("Nuevo nombre")
    expect(product.channel_prices).to be_empty
  end

  it "does not create the product when the ML price is invalid" do
    new_product = Product.new(attributes_for(:product))
    expect {
      described_class.call(product: new_product, attributes: {}, channel_prices: { "mercadolibre" => -5 })
    }.not_to change(Product, :count)
    expect(new_product).not_to be_persisted
  end

  it "ignores channels without their own price" do
    described_class.call(product: product, attributes: {}, channel_prices: { "whatsapp" => 12_000 })
    expect(product.reload.channel_prices).to be_empty
  end
end
