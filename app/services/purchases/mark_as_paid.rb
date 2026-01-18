# frozen_string_literal: true

module Purchases
  class MarkAsPaid
    def self.call(purchase:, payment_date: Date.today)
      new(purchase: purchase, payment_date: payment_date).call
    end

    def initialize(purchase:, payment_date:)
      @purchase = purchase
      @payment_date = payment_date
    end

    def call
      validate_params

      @purchase.mark_as_paid!(@payment_date)

      Result.new(success?: true, record: @purchase, errors: [])
    rescue ValidationError => e
      Result.new(success?: false, record: nil, errors: [ e.message ])
    rescue StandardError => e
      Rails.logger.error("Error in MarkAsPaid: #{e.message}")
      Result.new(success?: false, record: nil, errors: [ "Error marking purchase as paid" ])
    end

    private

    class ValidationError < StandardError; end

    def validate_params
      unless @purchase.simple_mode?
        raise ValidationError, "Only simple mode purchases can be marked as paid"
      end

      if @purchase.paid_status?
        raise ValidationError, "Purchase is already paid"
      end

      if @payment_date < @purchase.purchase_date
        raise ValidationError, "Payment date cannot be before purchase date"
      end
    end
  end
end
