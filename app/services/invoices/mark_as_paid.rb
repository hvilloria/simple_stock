# frozen_string_literal: true

module Invoices
  class MarkAsPaid
    def self.call(invoice:, payment_date: Date.today)
      new(invoice: invoice, payment_date: payment_date).call
    end

    def initialize(invoice:, payment_date:)
      @invoice = invoice
      @payment_date = payment_date
    end

    def call
      validate_params

      @invoice.mark_as_paid!(@payment_date)

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
    end
  end
end
