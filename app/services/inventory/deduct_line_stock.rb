# frozen_string_literal: true

module Inventory
  # Takes a sale line's quantity off the shelf, as far as there is stock to
  # take: the sale never fails for stock, and the count never goes below zero.
  class DeductLineStock
    def self.call(order_item:, note: nil)
      new(order_item: order_item, note: note).call
    end

    def initialize(order_item:, note: nil)
      @order_item = order_item
      @note = note
    end

    def call
      # The row lock keeps the floor true when two sales of the same product
      # race, provided the caller runs inside a transaction: AdjustStock opens
      # its own only after this read.
      product = Product.with_deleted.lock.find(@order_item.product_id)
      quantity = [ @order_item.quantity, product.current_stock ].min
      return Result.new(success?: true, record: nil, errors: []) unless quantity.positive?

      Inventory::AdjustStock.call(
        product: product,
        stock_location: StockLocation.first!,
        movement_type: "sale",
        quantity: -quantity,
        reference: @order_item,
        note: @note
      )
    rescue ActiveRecord::RecordNotFound => e
      Result.new(success?: false, record: nil, errors: [ e.message ])
    end
  end
end
