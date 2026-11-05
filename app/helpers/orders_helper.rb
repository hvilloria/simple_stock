# frozen_string_literal: true

module OrdersHelper
  def order_form_initial_items(order)
    order.order_items.select { |item| item.product.present? }.map do |item|
      product = item.product
      {
        product_id: item.product_id, sku: product.sku, name: product.name, brand: product.brand,
        quantity: item.quantity, price_unit: item.unit_price.to_f, channel_prices: product.channel_prices_map,
        base_price: product.price_unit.to_f, max_stock: product.current_stock, origin: product.origin,
        product_type: product.product_type, combo: product.combo?, components: product.search_components
      }
    end
  end
end
