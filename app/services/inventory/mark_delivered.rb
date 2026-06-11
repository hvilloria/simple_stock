# frozen_string_literal: true

module Inventory
  # Marks (or unmarks) the delivery of order_items on an on_account order.
  # Does not move stock yet (see spec out-of-scope: TRACK_STOCK refactor).
  class MarkDelivered
    def self.call(order:, order_item_ids:, delivered: true)
      new(order: order, order_item_ids: order_item_ids, delivered: delivered).call
    end

    def initialize(order:, order_item_ids:, delivered:)
      @order          = order
      @order_item_ids = Array(order_item_ids).map(&:to_i)
      @delivered      = delivered
    end

    def call
      unless @order.on_account_order_type?
        return Result.new(success?: false, record: nil, errors: [ "La operación no es un pago a cuenta" ])
      end

      ActiveRecord::Base.transaction do
        @order.order_items.where(id: @order_item_ids)
              .update_all(delivered_at: @delivered ? Time.current : nil)
      end

      Result.new(success?: true, record: @order, errors: [])
    rescue StandardError => e
      Rails.logger.error("Error in Inventory::MarkDelivered: #{e.message}")
      Result.new(success?: false, record: nil, errors: [ "Error registrando la entrega" ])
    end
  end
end
