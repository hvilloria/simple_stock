# frozen_string_literal: true

module Payments
  # Voids a collection together with every later one on the same notes (see
  # VoidCascade), newest first and all or nothing. Each note gets back what the
  # collection took off its debt, the allocations move to
  # voided_payment_allocations, and the cash gets a reversal on the
  # collection's own day, which the cascade guarantees is still open.
  class Void
    MISSING_REASON = "Falta indicar el motivo"
    CHANGED        = "Los cobros a anular cambiaron. Revisar la lista."

    def self.call(**params)
      new(**params).call
    end

    def initialize(payment:, user:, reason:, payment_ids:)
      @payment     = payment
      @user        = user
      @reason      = reason.to_s.strip
      @payment_ids = Array(payment_ids).map { |id| Integer(id, exception: false) }.sort_by(&:to_i)
    end

    def call
      raise ValidationError, MISSING_REASON if @reason.blank?

      voided = ActiveRecord::Base.transaction do
        @payment.lock!
        cascade = VoidCascade.call(payment: @payment)
        raise ValidationError, cascade.block if cascade.blocked?
        raise ValidationError, CHANGED unless cascade.ids == @payment_ids

        lock_rows!(cascade.payments)
        cascade.payments.each { |payment| void!(payment) }
        reset_sale_notes!
        @orders.each_value(&:refresh_status_from_balance!)
        cascade.payments
      end

      Result.new(success?: true, record: voided, errors: [])
    rescue ValidationError => e
      Result.new(success?: false, record: nil, errors: [ e.message ])
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, record: nil, errors: e.record.errors.full_messages)
    rescue StandardError => e
      Rails.logger.error("Error in Payments::Void: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      Result.new(success?: false, record: nil, errors: [ "Error anulando el cobro" ])
    end

    private

    class ValidationError < StandardError; end

    def lock_rows!(payments)
      Payment.where(id: payments.map(&:id)).order(:id).lock.load
      order_ids = payments.flat_map { |p| p.allocations.map(&:order_id) }.uniq
      @orders = Order.where(id: order_ids).order(:id).lock.index_by(&:id)
    end

    def void!(payment)
      payment.allocations.each do |allocation|
        give_back!(@orders.fetch(allocation.order_id), allocation)
        VoidedPaymentAllocation.create!(payment: payment, order_id: allocation.order_id,
                                        amount: allocation.amount,
                                        discount_amount: allocation.discount_amount,
                                        overpaid_amount: allocation.overpaid_amount)
        allocation.destroy!
      end

      reverse_cash!(payment)
      payment.update!(status: "voided", voided_at: Time.current, voided_by: @user, void_reason: @reason)
    end

    # The inverse of what the collection did to the note's total. A sale note
    # is reset whole once all its payments are gone (reset_sale_notes!).
    def give_back!(order, allocation)
      if order.on_account_order_type?
        order.update!(total_amount: order.total_amount + allocation.discount_amount - allocation.overpaid_amount)
      elsif order.credit_order_type? && allocation.overpaid_amount.positive?
        order.update!(total_amount: order.total_amount - allocation.overpaid_amount)
      end
    end

    def reset_sale_notes!
      @orders.each_value do |order|
        next unless order.immediate_order_type?

        order.order_items.each { |item| item.update!(discount_percent: 0) }
        order.update!(total_amount: order.original_total_amount)
      end
    end

    def reverse_cash!(payment)
      result = Cash::ReversePayment.call(
        payment:       payment,
        user:          @user,
        business_date: payment.original_cash_movement.business_date,
        description:   "Anulación del cobro ##{payment.id}: #{@reason}"
      )

      raise ValidationError, result.errors.join(", ") if result.failure?
    end
  end
end
