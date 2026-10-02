# frozen_string_literal: true

module Payments
  # The only writer of a payment's invoice. It never touches cash movements,
  # so it works on a day that is already closed.
  class AssignInvoice
    def self.call(**params)
      new(**params).call
    end

    def initialize(payment:, invoice_type:, invoice_number: nil)
      @payment        = payment
      @invoice_type   = invoice_type.presence
      @invoice_number = invoice_number.to_s.strip.presence
    end

    def call
      validate!

      @payment.update!(invoice_type: @invoice_type,
                       invoice_number: @invoice_type == "none" ? nil : @invoice_number)
      Result.new(success?: true, record: @payment, errors: [])
    rescue ValidationError => e
      Result.new(success?: false, record: nil, errors: [ e.message ])
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, record: nil, errors: e.record.errors.full_messages)
    end

    private

    class ValidationError < StandardError; end

    def validate!
      raise ValidationError, "Elegí el tipo de factura" if @invoice_type.nil?
      raise ValidationError, "Tipo de factura inválido" unless Payment.invoice_types.key?(@invoice_type)
      return unless %w[a b].include?(@invoice_type) && @invoice_number.nil?

      raise ValidationError, "El número es obligatorio para Factura A o B"
    end
  end
end
