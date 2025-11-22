# frozen_string_literal: true

module Payments
  class RegisterPayment
    def self.call(customer:, amount:, payment_method:, payment_date: nil, notes: nil)
      new(
        customer: customer,
        amount: amount,
        payment_method: payment_method,
        payment_date: payment_date,
        notes: notes
      ).call
    end

    def initialize(customer:, amount:, payment_method:, payment_date: nil, notes: nil)
      @customer = customer
      @amount = amount.to_f
      @payment_method = payment_method
      @payment_date = payment_date || Date.today
      @notes = notes
    end

    def call
      validate_params

      ActiveRecord::Base.transaction do
        create_payment

        Result.new(success?: true, record: @payment, errors: [])
      end
    rescue ValidationError => e
      Result.new(success?: false, record: nil, errors: [ e.message ])
    rescue StandardError => e
      Rails.logger.error("Error in Payments::RegisterPayment: #{e.message}")
      Result.new(success?: false, record: nil, errors: [ "Error registering payment" ])
    end

    private

    class ValidationError < StandardError; end

    def validate_params
      # Validar customer
      raise ValidationError, "Customer is required" if @customer.nil?

      # Validar que tenga cuenta corriente
      unless @customer.has_credit_account?
        raise ValidationError, "Customer does not have credit account enabled"
      end

      # Validar amount
      if @amount <= 0
        raise ValidationError, "Amount must be greater than zero"
      end

      # Validar payment_method
      unless Payment::PAYMENT_METHODS.include?(@payment_method)
        raise ValidationError, "Invalid payment method"
      end

      # Opcional: Validar que el pago no exceda el saldo
      # (comentado porque a veces se permite pagar de más)
      # current_balance = @customer.current_balance
      # if @amount > current_balance
      #   raise ValidationError, "Payment exceeds current balance ($#{current_balance})"
      # end
    end

    def create_payment
      @payment = Payment.create!(
        customer: @customer,
        amount: @amount,
        payment_method: @payment_method,
        payment_date: @payment_date,
        notes: @notes
      )
    end
  end
end
