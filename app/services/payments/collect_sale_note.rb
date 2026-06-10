# frozen_string_literal: true

module Payments
  # Collects payment on an immediate sale note (the cashier flow).
  #
  # Rules:
  #   - Order must be immediate + pending.
  #   - discount_percent in {0, 5, 10}; distributed to each order_item.
  #   - Tenders sum to effective total (original_total * (1 - discount/100)).
  #   - If discount > 0, every tender must be `cash` AND cover full total.
  class CollectSaleNote
    TOLERANCE = 0.01
    ALLOWED_DISCOUNTS = [ 0, 5, 10 ].freeze

    def self.call(order:, tenders:, discount_percent: 0, payment_date: Date.current)
      new(
        order: order,
        tenders: tenders,
        discount_percent: discount_percent,
        payment_date: payment_date
      ).call
    end

    def initialize(order:, tenders:, discount_percent:, payment_date:)
      @order            = order
      @tenders          = Array(tenders).map { |t| t.to_h.symbolize_keys }
      @discount_percent = discount_percent.to_i
      @payment_date     = payment_date || Date.current
    end

    def call
      validate!

      ActiveRecord::Base.transaction do
        apply_discount!
        create_payments_and_allocations!
        @order.refresh_status_from_balance!

        Result.new(success?: true, record: @order, errors: [])
      end
    rescue ValidationError => e
      Result.new(success?: false, record: nil, errors: [ e.message ])
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, record: nil, errors: e.record.errors.full_messages)
    rescue StandardError => e
      Rails.logger.error("Error in Payments::CollectSaleNote: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      Result.new(success?: false, record: nil, errors: [ "Error registrando el cobro" ])
    end

    private

    class ValidationError < StandardError; end

    def validate!
      unless @order.immediate_order_type? && @order.pending_status?
        raise ValidationError, "La nota no está pendiente o no es inmediata"
      end

      unless ALLOWED_DISCOUNTS.include?(@discount_percent)
        raise ValidationError, "Descuento inválido (0, 5 o 10)"
      end

      raise ValidationError, "Debe incluir al menos un pago" if @tenders.empty?

      @tenders.each do |t|
        amount = t[:amount].to_f
        raise ValidationError, "El monto debe ser mayor a cero" if amount <= 0
        unless Payment::PAYMENT_METHODS.include?(t[:payment_method])
          raise ValidationError, "Método de pago inválido: #{t[:payment_method]}"
        end
      end

      tender_sum = @tenders.sum { |t| t[:amount].to_f }

      if @discount_percent.positive?
        non_cash = @tenders.any? { |t| t[:payment_method] != "cash" }
        if non_cash || (tender_sum - effective_total).abs > TOLERANCE
          raise ValidationError, "Descuento solo permitido si el total se paga en efectivo"
        end
      elsif (tender_sum - effective_total).abs > TOLERANCE
        raise ValidationError,
              format("La suma de los pagos ($%.2f) debe coincidir con el total ($%.2f)", tender_sum, effective_total)
      end
    end

    def effective_total
      @effective_total ||= (@order.original_total_amount.to_d * (1 - @discount_percent.to_d / 100)).round(2)
    end

    def apply_discount!
      return if @discount_percent.zero?

      @order.order_items.each do |item|
        item.update!(discount_percent: @discount_percent)
      end

      new_total = @order.order_items.reload.sum do |oi|
        unit            = (oi.unit_price || 0).to_d
        discount_factor = 1 - oi.discount_percent.to_d / 100
        (unit * oi.quantity * discount_factor).round(2)
      end
      @order.update!(total_amount: new_total)
    end

    def create_payments_and_allocations!
      @tenders.group_by { |t| t[:payment_method] }.each do |method, rows|
        total = rows.sum { |r| r[:amount].to_f }
        payment = Payment.create!(
          customer:       @order.customer,
          amount:         total,
          payment_method: method,
          payment_date:   @payment_date
        )
        rows.each do |row|
          PaymentAllocation.create!(
            payment: payment,
            order:   @order,
            amount:  row[:amount].to_f
          )
        end
      end
    end
  end
end
