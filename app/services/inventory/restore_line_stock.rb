# frozen_string_literal: true

module Inventory
  # Puts back on the shelf whatever a sale line's own movements say is out.
  class RestoreLineStock
    def self.call(order_item:, note: nil)
      new(order_item: order_item, note: note).call
    end

    def initialize(order_item:, note: nil)
      @order_item = order_item
      @note = note
    end

    def call
      # Read the row rather than the line's cached product: AdjustStock writes
      # the recalculated stock with update!, which does nothing when a stale
      # instance already holds that value. The lock keeps two concurrent restores
      # from both adding back, provided the caller runs inside a transaction:
      # AdjustStock opens its own only after this read.
      product = Product.with_deleted.lock.find(@order_item.product_id)

      out = -@order_item.stock_movements.sum(:quantity)
      return Result.new(success?: true, record: nil, errors: []) unless out.positive?

      sale = @order_item.stock_movements.where(movement_type: "sale").order(:id).last

      Inventory::AdjustStock.call(
        product: product,
        stock_location: sale&.stock_location || StockLocation.first!,
        movement_type: "adjustment",
        quantity: out,
        reference: @order_item,
        note: @note
      )
    rescue ActiveRecord::RecordNotFound => e
      Result.new(success?: false, record: nil, errors: [ e.message ])
    end
  end
end
