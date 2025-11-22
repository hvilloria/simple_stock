module Sales
  class CancelOrder
    def self.call(order:, reason: nil)
      new(order: order, reason: reason).call
    end

    def initialize(order:, reason: nil)
      @order = order
      @reason = reason
    end

    def call
      validate_params

      ActiveRecord::Base.transaction do
        cancel_order
        reverse_stock_movements

        Result.new(success?: true, record: @order, errors: [])
      end
    rescue ValidationError => e
      Result.new(success?: false, record: nil, errors: [e.message])
    rescue StandardError => e
      Rails.logger.error("Error in Sales::CancelOrder: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      Result.new(success?: false, record: nil, errors: ['Error cancelling order'])
    end

    private

    class ValidationError < StandardError; end

    def validate_params
      raise ValidationError, 'Order is already cancelled' if @order.cancelled_status?
    end

    def cancel_order
      @order.update!(status: 'cancelled')
    end

    def reverse_stock_movements
      stock_location = StockLocation.first!

      @order.order_items.each do |item|
        result = Inventory::AdjustStock.call(
          product: item.product,
          stock_location: stock_location,
          movement_type: "adjustment",
          quantity: item.quantity,  # POSITIVO (reversa)
          reference: @order,
          note: @reason || "Order ##{@order.id} cancellation"
        )

        raise ValidationError, result.errors.join(", ") if result.failure?
      end
    end
  end
end
