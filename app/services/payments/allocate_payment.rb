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
      @payment_date = payment_date || Date.current
      @notes = notes
      @allocations = Array(allocations).map { |row| row.to_h.symbolize_keys }
    end

    def call
      validate_params

      payments = []
      ActiveRecord::Base.transaction do
        @allocations.each { |row| apply_discounts_for(row) }
        @allocations.each { |row| check_outstanding_after_discounts!(row) }

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

        @allocations.map { |row| row[:order_id] }.uniq.each do |oid|
          Order.find(oid).refresh_status_from_balance!
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

    # Backstop: callers must pass numeric (already-cleaned) amounts. A String
    # still carrying Argentine formatting (decimal comma / thousands separator)
    # would be silently truncated by #to_f (e.g. "80.000,00".to_f == 80.0), so
    # we fail loudly instead of registering an absurdly small payment.
    def reject_unparsed_amount_format!(raw)
      return unless raw.is_a?(String) && raw.include?(",")

      raise ValidationError, "Monto con formato inválido (debe venir numérico)"
    end

    def validate_params
      raise ValidationError, "Customer is required" if @customer.nil?

      unless @customer.has_credit_account?
        raise ValidationError, "El cliente no tiene cuenta corriente habilitada"
      end

      raise ValidationError, "Debe incluir al menos una orden" if @allocations.empty?

      @allocations.each do |row|
        reject_unparsed_amount_format!(row[:amount])

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

        unless order.credit_order_type? && !order.cancelled_status?
          raise ValidationError, "La orden ##{order.id} no es una venta a crédito activa"
        end
      end
    end

    def grouped_by_method
      @allocations.group_by { |row| row[:payment_method] }
    end

    def apply_discounts_for(row)
      raw = row[:item_discounts]
      return if raw.blank?

      order = Order.find(row[:order_id])
      # Discounts are frozen once any allocation has landed on the order.
      return if order.payment_allocations.exists?

      percents_by_item_id = raw.to_h.transform_keys(&:to_i).transform_values { |v| v.to_f }

      percents_by_item_id.each_value do |percent|
        if percent < 0 || percent > 20
          raise ValidationError, "Descuento fuera de rango (0-20%)"
        end
      end

      order.order_items.each do |item|
        next unless percents_by_item_id.key?(item.id)
        item.update!(discount_percent: percents_by_item_id[item.id])
      end

      new_total = order.order_items.reload.sum do |oi|
        unit = (oi.unit_price || 0).to_d
        discount_factor = 1 - oi.discount_percent.to_d / 100
        (unit * oi.quantity * discount_factor).round(2)
      end
      order.update!(total_amount: new_total)
    end

    def check_outstanding_after_discounts!(row)
      order = Order.find(row[:order_id])
      amount = row[:amount].to_f
      if amount > order.outstanding_balance
        raise ValidationError,
              "El monto excede el saldo pendiente de la orden ##{order.id} ($#{order.outstanding_balance})"
      end
    end
  end
end
