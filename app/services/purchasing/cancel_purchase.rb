# frozen_string_literal: true

module Purchasing
  class CancelPurchase
    def self.call(purchase:)
      new(purchase: purchase).call
    end

    def initialize(purchase:)
      @purchase = purchase
    end

    def call
      validate_params

      ActiveRecord::Base.transaction do
        cancel_purchase
        reverse_stock_movements
        recalculate_product_costs

        Result.new(success?: true, record: @purchase, errors: [])
      end
    rescue ValidationError => e
      Result.new(success?: false, record: nil, errors: [ e.message ])
    rescue StandardError => e
      Rails.logger.error("Error in Purchasing::CancelPurchase: #{e.message}")
      Result.new(success?: false, record: nil, errors: [ "Error cancelling purchase" ])
    end

    private

    class ValidationError < StandardError; end

    def validate_params
      raise ValidationError, "Purchase is already cancelled" if @purchase.cancelled_status?
    end

    def cancel_purchase
      @purchase.update!(status: "cancelled")
    end

    def reverse_stock_movements
      stock_location = StockLocation.first!

      @purchase.purchase_items.each do |purchase_item|
        result = Inventory::AdjustStock.call(
          product: purchase_item.product,
          stock_location: stock_location,
          movement_type: "adjustment",
          quantity: -purchase_item.quantity, # NEGATIVO (reversa)
          reference: @purchase,
          note: "Purchase ##{@purchase.id} cancellation"
        )

        raise ValidationError, result.errors.join(", ") if result.failure?
      end
    end

    def recalculate_product_costs
      @purchase.purchase_items.each do |item|
        item.product.recalculate_average_cost!
      end
    end
  end
end
