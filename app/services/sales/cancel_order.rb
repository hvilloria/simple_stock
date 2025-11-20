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
      raise ArgumentError, "Order already cancelled" if @order.cancelled_status?

      ActiveRecord::Base.transaction do
        stock_location = StockLocation.first!

        @order.order_items.each do |item|
          Inventory::AdjustStock.call(
            product:        item.product,
            stock_location: stock_location,
            movement_type:  :adjustment,
            quantity:       item.quantity,
            reference:      "ORDER-CANCEL-#{@order.id}",
            note:           @reason
          )
        end

        @order.update!(status: :cancelled)
      end

      @order
    end
  end
end
