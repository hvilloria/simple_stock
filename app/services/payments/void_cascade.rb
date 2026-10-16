# frozen_string_literal: true

module Payments
  # The payments a void takes with it: the chosen one and every later one on
  # the notes they cover, following a payment that covered several notes. A
  # sale note is collected in one go, so all its payments go together.
  class VoidCascade
    VOIDED      = "Este cobro ya está anulado."
    REVERSED    = "No se puede anular: el cobro #%<id>d ya se revirtió porque se anuló la venta."
    NO_MOVEMENT = "No se puede anular: el cobro #%<id>d no tiene movimiento de caja."
    CLOSED_DAY  = "No se puede anular: el cobro #%<id>d es del %<date>s y ese día de caja ya se cerró."

    Cascade = Struct.new(:payments, :block, keyword_init: true) do
      def blocked? = block.present?
      def total = payments.sum(&:amount)
      def ids = payments.map(&:id).sort
    end

    def self.call(payment:)
      new(payment: payment).call
    end

    def initialize(payment:)
      @payment = payment
    end

    def call
      payments = Payment.where(id: cascade_ids.to_a)
                        .includes(:customer, :cash_movements, allocations: :order)
                        .order(id: :desc).to_a
      Cascade.new(payments: payments, block: block_for(payments))
    end

    private

    def cascade_ids
      ids = Set[@payment.id]
      loop do
        grown = ids | later_ids(ids)
        return ids if grown == ids

        ids = grown
      end
    end

    def later_ids(ids)
      PaymentAllocation.where(payment_id: ids.to_a).includes(:order).group_by(&:order).flat_map do |order, allocations|
        scope = PaymentAllocation.where(order_id: order.id)
        unless order.immediate_order_type?
          scope = scope.where(payment_id: allocations.map(&:payment_id).min..)
                       .or(scope.where("overpaid_amount > 0"))
        end
        scope.pluck(:payment_id)
      end
    end

    def block_for(payments)
      return VOIDED if @payment.voided_status?

      payments.reverse_each do |payment|
        movement = payment.original_cash_movement
        return format(REVERSED, id: payment.id) if payment.reversal_movement
        return format(NO_MOVEMENT, id: payment.id) if movement.nil?
        if movement.sealed? || DailyClosing.exists?(business_date: movement.business_date)
          return format(CLOSED_DAY, id: payment.id, date: movement.business_date.strftime("%d/%m/%Y"))
        end
      end
      nil
    end
  end
end
