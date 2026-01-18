# frozen_string_literal: true

module Purchases
  class CreateSimplePurchase
    def self.call(supplier:, invoice_number:, amount:, currency:,
                  exchange_rate: nil, purchase_date: nil, due_date:, notes: nil)
      new(
        supplier: supplier,
        invoice_number: invoice_number,
        amount: amount,
        currency: currency,
        exchange_rate: exchange_rate,
        purchase_date: purchase_date,
        due_date: due_date,
        notes: notes
      ).call
    end

    def initialize(supplier:, invoice_number:, amount:, currency:,
                   exchange_rate: nil, purchase_date: nil, due_date:, notes: nil)
      @supplier = supplier
      @invoice_number = invoice_number
      @amount = amount
      @currency = currency
      @exchange_rate = exchange_rate
      @purchase_date = purchase_date || Date.today
      @due_date = due_date
      @notes = notes
    end

    def call
      validate_params

      @purchase = Purchase.create!(
        supplier: @supplier,
        invoice_number: @invoice_number,
        amount: @amount,
        currency: @currency,
        exchange_rate: @exchange_rate,
        purchase_date: @purchase_date,
        due_date: @due_date,
        status: "pending",
        has_items: false,
        notes: @notes
      )

      Result.new(success?: true, record: @purchase, errors: [])
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, record: nil, errors: [ e.record.errors.full_messages ])
    rescue ValidationError => e
      Result.new(success?: false, record: nil, errors: [ e.message ])
    rescue StandardError => e
      Rails.logger.error("Error in CreateSimplePurchase: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      Result.new(success?: false, record: nil, errors: [ "Error creating purchase" ])
    end

    private

    class ValidationError < StandardError; end

    def validate_params
      unless %w[USD ARS].include?(@currency)
        raise ValidationError, "Invalid currency. Must be USD or ARS"
      end

      if @currency == "USD" && (@exchange_rate.nil? || @exchange_rate <= 0)
        raise ValidationError, "Exchange rate required for USD purchases"
      end

      raise ValidationError, "Supplier is required" if @supplier.nil?
      raise ValidationError, "Invoice number is required" if @invoice_number.blank?

      unless @amount.to_f > 0
        raise ValidationError, "Amount must be greater than zero"
      end

      raise ValidationError, "Due date is required" if @due_date.nil?

      if @due_date < @purchase_date
        raise ValidationError, "Due date cannot be before purchase date"
      end
    end
  end
end
