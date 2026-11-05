# frozen_string_literal: true

module Inventory
  # Puts back on the shelf whatever a sale line's own movements say is out,
  # product by product: a combo line returns to each component what left for it.
  class RestoreLineStock
    def self.call(order_item:, note: nil)
      new(order_item: order_item, note: note).call
    end

    def initialize(order_item:, note: nil)
      @order_item = order_item
      @note = note
    end

    def call
      result = Result.new(success?: true, record: nil, errors: [])

      @order_item.stock_movements.distinct.order(:product_id).pluck(:product_id).each do |product_id|
        result = restore(product_id) || result
        return result if result.failure?
      end

      result
    rescue ActiveRecord::RecordNotFound => e
      Result.new(success?: false, record: nil, errors: [ e.message ])
    end

    private

    # Read the row rather than the line's cached product: AdjustStock writes
    # the recalculated stock with update!, which does nothing when a stale
    # instance already holds that value. The lock keeps two concurrent restores
    # from both adding back, provided the caller runs inside a transaction:
    # AdjustStock opens its own only after this read.
    def restore(product_id)
      product = Product.with_deleted.lock.find(product_id)
      movements = @order_item.stock_movements.where(product_id: product_id)

      out = -movements.sum(:quantity)
      return unless out.positive?

      sale = movements.where(movement_type: "sale").order(:id).last

      Inventory::AdjustStock.call(
        product: product,
        stock_location: sale&.stock_location || StockLocation.first!,
        movement_type: "adjustment",
        quantity: out,
        reference: @order_item,
        note: @note
      )
    end
  end
end
