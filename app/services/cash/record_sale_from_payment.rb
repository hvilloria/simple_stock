# frozen_string_literal: true

module Cash
  # Turns a collected payment into the sale movement that lands its money in an
  # arca. Writing goes through Cash::RecordMovement so there is a single write
  # path into cash_movements.
  class RecordSaleFromPayment
    def self.call(**params)
      new(**params).call
    end

    def initialize(payment:, user:, description: nil)
      @payment     = payment
      @user        = user
      @description = description
    end

    def call
      validate!

      RecordMovement.call(
        business_date:  @payment.payment_date,
        account:        CashMovement::CHANNEL_ACCOUNTS.fetch(channel),
        amount:         @payment.amount,
        category:       "sale",
        channel:        channel,
        description:    @description,
        source_payment: @payment,
        user:           @user
      )
    rescue ValidationError => e
      failure(e.message)
    rescue KeyError
      # channel_for_payment_method raises on a method with no cash channel.
      failure("El método de pago no corresponde a ningún canal de caja")
    rescue StandardError => e
      Rails.logger.error("Error in Cash::RecordSaleFromPayment: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      failure("Error registrando el cobro en caja")
    end

    private

    class ValidationError < StandardError; end

    def validate!
      raise ValidationError, "El pago es obligatorio" if @payment.blank?
      raise ValidationError, "El usuario es obligatorio" if @user.blank?
      # No unique index can express this: a reversing movement shares the
      # source_payment_id of the row it reverses.
      if CashMovement.exists?(source_payment_id: @payment.id)
        raise ValidationError, "Este pago ya fue registrado en caja"
      end
    end

    def channel
      @channel ||= CashMovement.channel_for_payment_method(@payment.payment_method)
    end

    def failure(message)
      Result.new(success?: false, record: nil, errors: [ message ])
    end
  end
end
