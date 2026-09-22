module Sales
  class CancelOrder
    def self.call(order:, user:, reason: nil)
      new(order: order, user: user, reason: reason).call
    end

    def initialize(order:, user:, reason: nil)
      @order = order
      @user = user
      @reason = reason
    end

    def call
      validate_params

      ActiveRecord::Base.transaction do
        cancel_order
        restore_stock
        reverse_cash_movements
        destroy_associated_allocations

        Result.new(success?: true, record: @order, errors: [])
      end
    rescue ValidationError => e
      Result.new(success?: false, record: nil, errors: [ e.message ])
    rescue StandardError => e
      Rails.logger.error("Error in Sales::CancelOrder: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      Result.new(success?: false, record: nil, errors: [ "Error cancelling order" ])
    end

    private

    class ValidationError < StandardError; end

    def validate_params
      raise ValidationError, "Order is already cancelled" if @order.cancelled_status?
      raise ValidationError, "El usuario es obligatorio" if @user.blank?
    end

    def cancel_order
      @order.update!(status: "cancelled", settled_on: nil)
    end

    # Back on the shelf goes what each line's own movements say is out: an
    # undelivered on_account line took nothing and gives nothing back.
    def restore_stock
      @order.order_items.each do |line|
        result = Inventory::RestoreLineStock.call(order_item: line, note: @reason.presence || "Cancelación nota #{@order.paper_number}")

        raise ValidationError, result.errors.join(", ") if result.failure?
      end
    end

    # Runs before the allocations are destroyed, which are the only way back to
    # the payments. Cash::ReversePayment mirrors a movement whole, so it can only
    # be used on a payment this order owns outright: a payment split across
    # several orders is left standing, because its money still backs the ones
    # that survive.
    def reverse_cash_movements
      exclusively_allocated_payments.each do |payment|
        next unless CashMovement.exists?(source_payment_id: payment.id)

        result = Cash::ReversePayment.call(payment: payment, user: @user)

        raise ValidationError, result.errors.join(", ") if result.failure?
      end
    end

    def exclusively_allocated_payments
      Payment
        .where(id: @order.payment_allocations.select(:payment_id))
        .where.not(id: PaymentAllocation.where.not(order_id: @order.id).select(:payment_id))
    end

    # The Payment outlives its allocations on purpose: cash_movements.source_payment_id
    # points at it, and the reversal row means nothing without the payment it names.
    # Keeping it costs nothing — Customer#current_balance only counts allocations of
    # live orders, so a payment left with none stops weighing on any balance.
    def destroy_associated_allocations
      @order.payment_allocations.destroy_all
    end
  end
end
