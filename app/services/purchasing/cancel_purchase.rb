# frozen_string_literal: true

module Purchasing
  class CancelPurchase
    def self.call(invoice:)
      new(invoice: invoice).call
    end

    def initialize(invoice:)
      @invoice = invoice
    end

    def call
      validate_params

      ActiveRecord::Base.transaction do
        cancel_invoice_record
        reverse_stock_movements
        recalculate_product_costs

        Result.new(success?: true, record: @invoice, errors: [])
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
      raise ValidationError, "Invoice is already cancelled" if @invoice.cancelled_status?
    end

    def cancel_invoice_record
      @invoice.update!(status: "cancelled")
    end

    def reverse_stock_movements
      stock_location = StockLocation.first!

      @invoice.invoice_items.each do |invoice_item|
        result = Inventory::AdjustStock.call(
          product: invoice_item.product,
          stock_location: stock_location,
          movement_type: "adjustment",
          quantity: -invoice_item.quantity, # NEGATIVO (reversa)
          reference: @invoice,
          note: "Invoice ##{@invoice.id} cancellation"
        )

        raise ValidationError, result.errors.join(", ") if result.failure?
      end
    end

    def recalculate_product_costs
      @invoice.invoice_items.each do |item|
        item.product.recalculate_average_cost!
      end
    end
  end
end
