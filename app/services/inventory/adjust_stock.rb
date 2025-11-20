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
      validate_params
      
      ActiveRecord::Base.transaction do
        create_stock_movement
        update_product_stock
        
        Result.new(success?: true, record: @stock_movement, errors: [])
      end
    rescue ValidationError => e
      Result.new(success?: false, record: nil, errors: [e.message])
    rescue StandardError => e
      Rails.logger.error("Error in Inventory::AdjustStock: #{e.message}")
      Result.new(success?: false, record: nil, errors: ['Error adjusting stock'])
    end

    private

    class ValidationError < StandardError; end

    def validate_params
      raise ValidationError, "Quantity cannot be zero" if @quantity.zero?

      # Validate that resulting stock won't be negative
      projected_stock = @product.current_stock + @quantity
      if projected_stock.negative?
        raise ValidationError, "Insufficient stock to perform this operation"
      end
    end

    def create_stock_movement
      @stock_movement = StockMovement.create!(
        product:        @product,
        stock_location: @stock_location,
        quantity:       @quantity,
        movement_type:  @movement_type,
        reference:      @reference,
        note:           @note
      )
    end

    def update_product_stock
      # Recalcular stock desde stock_movements en lugar de editar manualmente
      @product.recalculate_current_stock!
    end
  end
end
