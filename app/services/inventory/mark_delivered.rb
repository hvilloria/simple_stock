# frozen_string_literal: true

module Inventory
  # Marks (or unmarks) the delivery of order_items on an on_account order. A
  # line leaves the shelf when it is delivered and comes back if the delivery
  # is undone; a line already in the asked state is left alone.
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

      if @order.cancelled_status?
        return Result.new(success?: false, record: nil, errors: [ "La operación está anulada" ])
      end

      ActiveRecord::Base.transaction do
        lines.each { |line| @delivered ? deliver(line) : undo(line) }
      end

      Result.new(success?: true, record: @order, errors: [])
    rescue ValidationError => e
      Result.new(success?: false, record: nil, errors: [ e.message ])
    rescue StandardError => e
      Rails.logger.error("Error in Inventory::MarkDelivered: #{e.message}")
      Result.new(success?: false, record: nil, errors: [ "Error registrando la entrega" ])
    end

    private

    class ValidationError < StandardError; end

    def lines
      @order.order_items.where(id: @order_item_ids).lock
    end

    def deliver(line)
      return if line.delivered_at.present?

      line.update!(delivered_at: Time.current)
      unwrap!(Inventory::DeductLineStock.call(order_item: line, note: "Entrega nota #{@order.paper_number}"))
    end

    def undo(line)
      return if line.delivered_at.nil?

      unwrap!(Inventory::RestoreLineStock.call(order_item: line, note: "Entrega deshecha nota #{@order.paper_number}"))
      line.update!(delivered_at: nil)
    end

    def unwrap!(result)
      raise ValidationError, result.errors.join(", ") if result.failure?
    end
  end
end
