# frozen_string_literal: true

module Inventory
  # Takes a sale line's quantity off the shelf, as far as there is stock to
  # take: the sale never fails for stock, and the count never goes below zero.
  # A combo line takes each of its components instead, each floored on its own.
  class DeductLineStock
    def self.call(order_item:, note: nil)
      new(order_item: order_item, note: note).call
    end

    def initialize(order_item:, note: nil)
      @order_item = order_item
      @note = note
    end

    def call
      result = Result.new(success?: true, record: nil, errors: [])

      @order_item.stock_lines.each do |product_id, wanted|
        result = deduct(product_id, wanted) || result
        return result if result.failure?
      end

      result
    rescue ActiveRecord::RecordNotFound => e
      Result.new(success?: false, record: nil, errors: [ e.message ])
    end

    private

    # The row lock keeps the floor true when two sales of the same product
    # race, provided the caller runs inside a transaction: AdjustStock opens
    # its own only after this read. Products are locked in id order.
    def deduct(product_id, wanted)
      product = Product.with_deleted.lock.find(product_id)
      quantity = [ wanted, product.current_stock ].min
      return unless quantity.positive?

      Inventory::AdjustStock.call(
        product: product,
        stock_location: StockLocation.first!,
        movement_type: "sale",
        quantity: -quantity,
        reference: @order_item,
        note: @note
      )
    end
  end
end
