# frozen_string_literal: true

module Invoices
  # Cancels a pending invoice and takes back the stock it added, as far as
  # there is stock to take.
  class CancelInvoice
    def self.call(invoice:)
      new(invoice: invoice).call
    end

    def initialize(invoice:)
      @invoice = invoice
    end

    def call
      validate!

      ActiveRecord::Base.transaction do
        reverse_stock
        @invoice.update!(status: "cancelled")

        Result.new(success?: true, record: @invoice, errors: [])
      end
    rescue ValidationError => e
      Result.new(success?: false, record: nil, errors: [ e.message ])
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, record: nil, errors: e.record.errors.full_messages)
    rescue StandardError => e
      Rails.logger.error("Error in Invoices::CancelInvoice: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      Result.new(success?: false, record: nil, errors: [ "Error al cancelar la factura" ])
    end

    private

    class ValidationError < StandardError; end

    def validate!
      raise ValidationError, "Solo se pueden cancelar facturas pendientes" unless @invoice.pending_status?
    end

    # The purchase rows stay as history; what comes back is what the invoice
    # added, capped at what is still on the shelf.
    def reverse_stock
      purchased_by_product.each do |(product_id, location_id), purchased|
        product = Product.with_deleted.lock.find(product_id)
        quantity = [ purchased, product.current_stock ].min
        next unless quantity.positive?

        result = Inventory::AdjustStock.call(
          product: product,
          stock_location: StockLocation.find(location_id),
          movement_type: "adjustment",
          quantity: -quantity,
          reference: @invoice,
          note: "Cancelación de factura #{@invoice.invoice_number}"
        )
        raise ValidationError, result.errors.join(", ") if result.failure?
      end
    end

    def purchased_by_product
      @invoice.stock_movements
              .where(movement_type: "purchase")
              .group(:product_id, :stock_location_id)
              .sum(:quantity)
    end
  end
end
