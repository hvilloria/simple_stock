# frozen_string_literal: true

module Payments
  # Collects a partial, repeatable payment on an on_account sale.
  #
  # Rules:
  #   - Order must be on_account and not cancelled.
  #   - amount_to_settle in (0, outstanding_balance].
  #   - discount_percent in {0, 5, 10}; if > 0 every tender must be cash.
  #   - Tenders sum to amount_to_settle * (1 - discount/100).
  #   - The discount lowers total_amount (absorbed by the shop), not the debt.
  class CollectOnAccount
    include Payments::CashRounding

    TOLERANCE = 0.01
    ALLOWED_DISCOUNTS = [ 0, 5, 10 ].freeze

    def self.call(order:, amount_to_settle:, tenders:, discount_percent: 0, payment_date: Date.current)
      new(
        order: order,
        amount_to_settle: amount_to_settle,
        tenders: tenders,
        discount_percent: discount_percent,
        payment_date: payment_date
      ).call
    end

    def initialize(order:, amount_to_settle:, tenders:, discount_percent:, payment_date:)
      @order            = order
      @amount_to_settle = amount_to_settle.to_d
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
      Rails.logger.error("Error in Payments::CollectOnAccount: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      Result.new(success?: false, record: nil, errors: [ "Error registrando el cobro" ])
    end

    private

    class ValidationError < StandardError; end

    def validate!
      unless @order.on_account_order_type? && !@order.cancelled_status?
        raise ValidationError, "La operación no es un pago a cuenta activo"
      end

      unless ALLOWED_DISCOUNTS.include?(@discount_percent)
        raise ValidationError, "Descuento inválido (0, 5 o 10)"
      end

      if @amount_to_settle <= 0
        raise ValidationError, "El monto a cancelar debe ser mayor a cero"
      end

      if @amount_to_settle > @order.outstanding_balance
        raise ValidationError, "El monto a cancelar supera el saldo pendiente"
      end

      raise ValidationError, "Debe incluir al menos un pago" if @tenders.empty?

      @tenders.each do |t|
        amount = t[:amount].to_f
        raise ValidationError, "El monto debe ser mayor a cero" if amount <= 0
        unless Payment::PAYMENT_METHODS.include?(t[:payment_method])
          raise ValidationError, "Método de pago inválido: #{t[:payment_method]}"
        end
      end

      if @discount_percent.positive? && @tenders.any? { |t| t[:payment_method] != "cash" }
        raise ValidationError, "Descuento solo permitido si el cobro es en efectivo"
      end

      tender_sum = @tenders.sum { |t| t[:amount].to_d }
      if (tender_sum - cash_to_collect).abs > TOLERANCE
        raise ValidationError,
              format("La suma de los pagos ($%.2f) debe coincidir con el efectivo a cobrar ($%.2f)",
                     tender_sum, cash_to_collect)
      end
    end

    def discount_value
      @discount_value ||= (@amount_to_settle * @discount_percent / 100).round(2)
    end

    def cash_to_collect
      @cash_to_collect ||= begin
        raw = (@amount_to_settle - discount_value).round(2)
        @discount_percent.positive? ? round_to_nearest_hundred(raw) : raw
      end
    end

    def apply_discount!
      # Lower total_amount by the EFFECTIVE discount (settle − rounded cash) so the
      # balance closes exactly against the nearest-hundred allocation.
      effective_discount = @amount_to_settle - cash_to_collect
      return if effective_discount.zero?
      @order.update!(total_amount: @order.total_amount - effective_discount)
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
          PaymentAllocation.create!(payment: payment, order: @order, amount: row[:amount].to_f)
        end
      end
    end
  end
end
