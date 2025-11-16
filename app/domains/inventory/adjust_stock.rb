module Inventory
  class AdjustStock
    def self.call(product:, stock_location:, movement_type:, quantity:, reference: nil, note: nil)
      new(
        product:        product,
        stock_location: stock_location,
        movement_type:  movement_type,
        quantity:       quantity,
        reference:      reference,
        note:           note
      ).call
    end

    def initialize(product:, stock_location:, movement_type:, quantity:, reference:, note:)
      @product        = product
      @stock_location = stock_location
      @movement_type  = movement_type.to_sym
      @quantity       = quantity.to_i
      @reference      = reference
      @note           = note
    end

    def call
      raise ArgumentError, "quantity cannot be 0" if @quantity.zero?

      ActiveRecord::Base.transaction do
        StockMovement.create!(
          product:        @product,
          stock_location: @stock_location,
          quantity:       @quantity,
          movement_type:  @movement_type,
          reference:      @reference,
          note:           @note
        )

        @product.update!(current_stock: @product.current_stock + @quantity)
      end

      @product
    end
  end
end
