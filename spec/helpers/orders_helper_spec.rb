require "rails_helper"

RSpec.describe OrdersHelper, type: :helper do
  describe "#order_form_initial_items" do
    it "carries a regular line as a non-combo item without components" do
      product = create(:product, sku: "BUJE-1", price_unit: 10_000)
      order = Order.new
      order.order_items.build(product: product, quantity: 2, unit_price: product.price_unit)

      item = helper.order_form_initial_items(order).sole

      expect(item).to include(product_id: product.id, sku: "BUJE-1", quantity: 2, price_unit: 10_000.0,
                              combo: false, components: [])
    end

    it "carries a combo line with its components" do
      part = create(:product, sku: "12345-123-12345", name: "Amortiguador izq.")
      combo = create(:product, :combo, components: [ [ part, 1 ] ], price_unit: 100_000)
      order = Order.new
      order.order_items.build(product: combo, quantity: 1, unit_price: combo.price_unit)

      item = helper.order_form_initial_items(order).sole

      expect(item).to include(combo: true)
      expect(item[:components]).to eq([ { sku: "12345-123-12345", name: "Amortiguador izq.", quantity: 1,
                                          current_stock: part.current_stock } ])
    end

    it "skips lines without a product" do
      order = Order.new
      order.order_items.build

      expect(helper.order_form_initial_items(order)).to eq([])
    end
  end
end
