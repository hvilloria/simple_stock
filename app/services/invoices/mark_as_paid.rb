# frozen_string_literal: true

module Invoices
  class MarkAsPaid
    def self.call(invoice:, payment_date: Date.today, apply_discount: false)
      new(invoice: invoice, payment_date: payment_date, apply_discount: apply_discount).call
    end

    def initialize(invoice:, payment_date:, apply_discount: false)
      @invoice = invoice
      @payment_date = payment_date
      @apply_discount = apply_discount
    end

    def call
      validate_params

      ActiveRecord::Base.transaction do
        @invoice.update!(
          status: "paid",
          paid_at: @payment_date,
          paid_with_discount: @apply_discount
        )

        # Marcar notas de crédito asociadas como aplicadas
        @invoice.credit_notes.pending_status.update_all(
          status: "applied",
          applied_at: @payment_date
        )
      end

      Result.new(success?: true, record: @invoice, errors: [])
    rescue ValidationError => e
      Result.new(success?: false, record: nil, errors: [ e.message ])
    rescue StandardError => e
      Rails.logger.error("Error in MarkAsPaid: #{e.message}")
      Result.new(success?: false, record: nil, errors: [ "Error marking invoice as paid" ])
    end

    private

    class ValidationError < StandardError; end

    def validate_params
      unless @invoice.simple_mode?
        raise ValidationError, "Only simple mode invoices can be marked as paid"
      end

      if @invoice.paid_status?
        raise ValidationError, "Invoice is already paid"
      end

      if @payment_date < @invoice.purchase_date
        raise ValidationError, "Payment date cannot be before invoice date"
      end

      # Validar descuento si se intenta aplicar
      if @apply_discount && !@invoice.eligible_for_discount?(@payment_date)
        raise ValidationError, "Discount has expired or is not available for this invoice"
      end
    end
  end
end
