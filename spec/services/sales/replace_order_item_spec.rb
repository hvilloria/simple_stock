require "rails_helper"

RSpec.describe Sales::ReplaceOrderItem do
  let(:order) { create(:order, :on_account, total_amount: 1000, original_total_amount: 1000) }
  let(:old_product) { create(:product, price_unit: 500) }
  let(:new_product) { create(:product, price_unit: 300) }
  let!(:item) { create(:order_item, order: order, product: old_product, quantity: 2, unit_price: 500) }

  it "swaps the product at catalog price and applies the delta to both totals" do
    result = described_class.call(order_item: item, product_id: new_product.id, quantity: 2)

    expect(result).to be_success
    item.reload
    expect(item.product).to eq(new_product)
    expect(item.unit_price).to eq(300)
    expect(item.quantity).to eq(2)
    # delta = (2*300) - (2*500) = -400
    expect(order.reload.total_amount).to eq(600)
    expect(order.original_total_amount).to eq(600)
  end

  it "keeps the original line price on a quantity-only edit" do
    catalog_moved = item.product
    catalog_moved.update!(price_unit: 999)

    result = described_class.call(order_item: item, product_id: catalog_moved.id, quantity: 3)

    expect(result).to be_success
    item.reload
    expect(item.unit_price).to eq(500) # NOT 999
    expect(item.quantity).to eq(3)
    # delta = (3*500) - (2*500) = 500
    expect(order.reload.total_amount).to eq(1500)
    expect(order.original_total_amount).to eq(1500)
  end

  it "preserves the original-minus-total gap left by discounted collections" do
    # Simulate a prior discounted collection: total lowered, original untouched
    order.update!(total_amount: 900)

    described_class.call(order_item: item, product_id: new_product.id, quantity: 2)

    order.reload
    # gap (original - total) must stay 100
    expect(order.original_total_amount - order.total_amount).to eq(100)
  end

  it "reopens a confirmed order when the swap makes it owe money again" do
    create(:payment_allocation, order: order,
           payment: create(:payment, customer: order.customer, amount: 1000), amount: 1000)
    order.refresh_status_from_balance!
    expect(order.reload.status).to eq("confirmed")

    pricier = create(:product, price_unit: 800)
    described_class.call(order_item: item, product_id: pricier.id, quantity: 2)

    expect(order.reload.status).to eq("pending")
  end

  it "rejects an already delivered item" do
    item.update!(delivered_at: Time.current)
    result = described_class.call(order_item: item, product_id: new_product.id, quantity: 2)

    expect(result).to be_failure
    expect(result.errors).to include("El producto ya fue entregado")
    expect(item.reload.product).to eq(old_product)
  end

  it "rejects a non on_account order" do
    immediate = create(:order, order_type: "immediate", total_amount: 100, original_total_amount: 100)
    other_item = create(:order_item, order: immediate, product: old_product, quantity: 1, unit_price: 100)

    result = described_class.call(order_item: other_item, product_id: new_product.id, quantity: 1)
    expect(result).to be_failure
  end

  it "rejects a cancelled order" do
    order.update!(status: "cancelled")
    result = described_class.call(order_item: item, product_id: new_product.id, quantity: 2)
    expect(result).to be_failure
  end

  it "rejects quantity below 1" do
    result = described_class.call(order_item: item, product_id: new_product.id, quantity: 0)
    expect(result).to be_failure
    expect(result.errors).to include("La cantidad debe ser mayor a cero")
  end

  it "rejects an unknown product" do
    result = described_class.call(order_item: item, product_id: -1, quantity: 2)
    expect(result).to be_failure
    expect(result.errors).to include("Producto inválido")
  end

  it "rejects an inactive product" do
    inactive = create(:product, :inactive, price_unit: 300)
    result = described_class.call(order_item: item, product_id: inactive.id, quantity: 2)
    expect(result).to be_failure
  end

  it "rejects a soft-deleted product" do
    deleted = create(:product, price_unit: 300)
    deleted.destroy
    result = described_class.call(order_item: item, product_id: deleted.id, quantity: 2)
    expect(result).to be_failure
  end

  it "rejects a product without catalog price" do
    no_price = create(:product, price_unit: 0)
    result = described_class.call(order_item: item, product_id: no_price.id, quantity: 2)

    expect(result).to be_failure
    expect(result.errors).to include("El producto no tiene precio de catálogo — cargalo en Productos")
  end

  it "rejects a swap that would drive the order total negative" do
    discounted_order = create(:order, :on_account, total_amount: 90_000, original_total_amount: 100_000)
    line_item = create(:order_item, order: discounted_order, product: old_product, quantity: 1, unit_price: 100_000)
    cheap = create(:product, price_unit: 5_000)

    result = described_class.call(order_item: line_item, product_id: cheap.id, quantity: 1)

    expect(result).to be_failure
    expect(result.errors).to include("El cambio dejaría la operación con un total negativo")
    expect(line_item.reload.product).to eq(old_product)
    expect(discounted_order.reload.total_amount).to eq(90_000)
    expect(discounted_order.original_total_amount).to eq(100_000)
  end

  it "rejects a swap that lands the projected total on exactly 0 (live order)" do
    zero_order = create(:order, :on_account, total_amount: 500, original_total_amount: 500)
    line_item = create(:order_item, order: zero_order, product: old_product, quantity: 2, unit_price: 500)

    # delta = (1*500) - (2*500) = -500; projected total = 500 - 500 = 0
    result = described_class.call(order_item: line_item, product_id: old_product.id, quantity: 1)

    expect(result).to be_failure
    expect(result.errors).to include("El cambio dejaría la operación con un total en cero")
    expect(line_item.reload.quantity).to eq(2)
    expect(zero_order.reload.total_amount).to eq(500)
    expect(zero_order.original_total_amount).to eq(500)
  end

  it "allows a swap that leaves the total below the collected amount (known gap)" do
    create(:payment_allocation, order: order,
           payment: create(:payment, customer: order.customer, amount: 800), amount: 800)

    cheap = create(:product, price_unit: 100)
    result = described_class.call(order_item: item, product_id: cheap.id, quantity: 2)

    expect(result).to be_success
    order.reload
    expect(order.total_amount).to eq(200)
    expect(order.outstanding_balance).to eq(-600)
    expect(order.status).to eq("confirmed")
  end

  it "does not create a StockMovement" do
    expect {
      described_class.call(order_item: item, product_id: new_product.id, quantity: 2)
    }.not_to change(StockMovement, :count)
  end
end
