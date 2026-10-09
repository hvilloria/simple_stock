# frozen_string_literal: true

module Payments
  # Corrects the payment method of a collection while its cash day is open: the
  # payment and its cash movement change in place, the movement following the
  # new method to its channel and arca.
  class ChangeMethod
    SAME_METHOD   = "El cobro ya está registrado con ese medio de pago"
    NO_MOVEMENT   = "Este cobro no tiene movimiento de caja"
    REVERSED      = "Este cobro fue revertido: no se puede cambiar el medio de pago"
    CLOSED_DAY    = "El día %s ya se cerró: el medio de pago no se puede cambiar."
    CASH_DISCOUNT = "Este cobro tuvo descuento en efectivo: no se puede pasar a otro medio."

    def self.call(**params)
      new(**params).call
    end

    def initialize(payment:, payment_method:)
      @payment        = payment
      @payment_method = payment_method.to_s.presence
    end

    def call
      ActiveRecord::Base.transaction do
        @payment.lock!
        validate!

        movement = @payment.original_cash_movement
        movement.lock!
        channel = CashMovement.channel_for_payment_method(@payment_method)
        @payment.update!(payment_method: @payment_method)
        movement.update!(channel: channel, account: CashMovement.account_for_channel(channel))
      end

      Result.new(success?: true, record: @payment, errors: [])
    rescue ValidationError => e
      Result.new(success?: false, record: nil, errors: [ e.message ])
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, record: nil, errors: e.record.errors.full_messages)
    rescue StandardError => e
      Rails.logger.error("Error in Payments::ChangeMethod: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      Result.new(success?: false, record: nil, errors: [ "Error cambiando el medio de pago" ])
    end

    private

    class ValidationError < StandardError; end

    def validate!
      raise ValidationError, Payment::MISSING_METHOD_ERROR if @payment_method.nil?
      unless Payment::PAYMENT_METHODS.include?(@payment_method)
        raise ValidationError, "Método de pago inválido: #{@payment_method}"
      end
      raise ValidationError, SAME_METHOD if @payment_method == @payment.payment_method

      case @payment.method_change_block
      when :locked
        raise ValidationError, @payment.original_cash_movement ? REVERSED : NO_MOVEMENT
      when :closed
        raise ValidationError, format(CLOSED_DAY, @payment.original_cash_movement.business_date.strftime("%d/%m/%Y"))
      when :cash_discount
        raise ValidationError, CASH_DISCOUNT
      end
    end
  end
end
