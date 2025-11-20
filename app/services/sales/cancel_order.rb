module Sales
  class CancelOrder
    def self.call(order:, reason: nil)
      new(order: order, reason: reason).call
    end

    def initialize(order:, reason:)
      @order  = order
      @reason = reason
    end

    def call
      validate_params
      
      ActiveRecord::Base.transaction do
        restore_stock
        cancel_order
        
        Result.new(success?: true, record: @order, errors: [])
      end
    rescue ValidationError => e
      Result.new(success?: false, record: nil, errors: [e.message])
    rescue StandardError => e
      Rails.logger.error("Error in Sales::CancelOrder: #{e.message}")
      Result.new(success?: false, record: nil, errors: ['Error cancelling order'])
    end

    private

    class ValidationError < StandardError; end

    def validate_params
      raise ValidationError, "Order is already cancelled" if @order.cancelled_status?
    end

    def restore_stock
      stock_location = StockLocation.first!

      @order.order_items.each do |item|
        result = Inventory::AdjustStock.call(
          product:        item.product,
          stock_location: stock_location,
          movement_type:  :adjustment,
          quantity:       item.quantity,
          reference:      "ORDER-CANCEL-#{@order.id}",
          note:           @reason
        )

        raise ValidationError, result.errors.join(", ") if result.failure?
      end
    end

    def cancel_order
      @order.update!(status: :cancelled)
    end
  end
end
