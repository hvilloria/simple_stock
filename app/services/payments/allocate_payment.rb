# frozen_string_literal: true

module Payments
  class AllocatePayment
    def self.call(customer:, payment_date:, allocations:, notes: nil)
      new(
        customer: customer,
        payment_date: payment_date,
        allocations: allocations,
        notes: notes
      ).call
    end

    def initialize(customer:, payment_date:, allocations:, notes: nil)
      @customer = customer
      @payment_date = payment_date || Date.today
      @notes = notes
      @allocations = Array(allocations).map { |row| row.to_h.symbolize_keys }
    end

    def call
      validate_params

      payments = []
      ActiveRecord::Base.transaction do
        grouped_by_method.each do |method, rows|
          total = rows.sum { |r| r[:amount].to_f }
          payment = Payment.create!(
            customer: @customer,
            amount: total,
            payment_method: method,
            payment_date: @payment_date,
            notes: @notes
          )

          rows.each do |row|
            PaymentAllocation.create!(
              payment: payment,
              order_id: row[:order_id],
              amount: row[:amount].to_f
            )
          end

          payments << payment
        end

        Result.new(success?: true, record: payments, errors: [])
      end
    rescue ValidationError => e
      Result.new(success?: false, record: nil, errors: [ e.message ])
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, record: nil, errors: e.record.errors.full_messages)
    rescue StandardError => e
      Rails.logger.error("Error in Payments::AllocatePayment: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      Result.new(success?: false, record: nil, errors: [ "Error registrando el cobro" ])
    end

    private

    class ValidationError < StandardError; end

    def validate_params
      raise ValidationError, "Customer is required" if @customer.nil?

      unless @customer.has_credit_account?
        raise ValidationError, "El cliente no tiene cuenta corriente habilitada"
      end

      raise ValidationError, "Debe incluir al menos una orden" if @allocations.empty?

      @allocations.each do |row|
        amount = row[:amount].to_f
        raise ValidationError, "El monto debe ser mayor a cero" if amount <= 0

        unless Payment::PAYMENT_METHODS.include?(row[:payment_method])
          raise ValidationError, "Método de pago inválido: #{row[:payment_method]}"
        end

        order = Order.find_by(id: row[:order_id])
        raise ValidationError, "Orden no encontrada (id #{row[:order_id]})" if order.nil?

        if order.customer_id != @customer.id
          raise ValidationError, "La orden ##{order.id} no pertenece al cliente"
        end

        unless order.credit_order_type? && order.confirmed_status?
          raise ValidationError, "La orden ##{order.id} no es una venta a crédito confirmada"
        end

        if amount > order.outstanding_balance
          raise ValidationError, "El monto excede el saldo pendiente de la orden ##{order.id} ($#{order.outstanding_balance})"
        end
      end
    end

    def grouped_by_method
      @allocations.group_by { |row| row[:payment_method] }
    end
  end
end
