# frozen_string_literal: true

module Invoices
  # Registers a supplier invoice. With product lines it also stocks them and
  # takes its amount from them; without lines it is the amount-only invoice.
  class CreateInvoice
    Line = Struct.new(:product, :quantity, :unit_cost, keyword_init: true)

    def self.call(supplier:, invoice_number:, amount:, currency:,
                  exchange_rate: nil, purchase_date: nil, due_date:, notes: nil,
                  early_payment_due_date: nil, early_payment_discount_percentage: nil,
                  items: [])
      new(
        supplier: supplier,
        invoice_number: invoice_number,
        amount: amount,
        currency: currency,
        exchange_rate: exchange_rate,
        purchase_date: purchase_date,
        due_date: due_date,
        notes: notes,
        early_payment_due_date: early_payment_due_date,
        early_payment_discount_percentage: early_payment_discount_percentage,
        items: items
      ).call
    end

    def initialize(supplier:, invoice_number:, amount:, currency:,
                   exchange_rate: nil, purchase_date: nil, due_date:, notes: nil,
                   early_payment_due_date: nil, early_payment_discount_percentage: nil,
                   items: [])
      @supplier = supplier
      @invoice_number = invoice_number
      @amount = amount
      @currency = currency
      @exchange_rate = exchange_rate
      @purchase_date = purchase_date || Date.current
      @due_date = due_date
      @notes = notes
      @early_payment_due_date = early_payment_due_date
      @early_payment_discount_percentage = early_payment_discount_percentage
      @items = Array(items).map { |item| item.to_h.symbolize_keys }
    end

    def call
      validate_params

      ActiveRecord::Base.transaction do
        build_invoice
        build_lines
        @invoice.save!
        move_stock

        Result.new(success?: true, record: @invoice, errors: [])
      end
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, record: nil, errors: e.record.errors.full_messages)
    rescue ValidationError => e
      Result.new(success?: false, record: nil, errors: [ e.message ])
    rescue StandardError => e
      Rails.logger.error("Error in Invoices::CreateInvoice: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      Result.new(success?: false, record: nil, errors: [ "Error creating invoice" ])
    end

    private

    class ValidationError < StandardError; end

    def validate_params
      unless %w[USD ARS].include?(@currency)
        raise ValidationError, "Invalid currency. Must be USD or ARS"
      end

      if @currency == "USD" && (@exchange_rate.nil? || @exchange_rate <= 0)
        raise ValidationError, "Exchange rate required for USD invoices"
      end

      raise ValidationError, "Supplier is required" if @supplier.nil?
      raise ValidationError, "Invoice number is required" if @invoice_number.blank?

      if lines.empty? && !(@amount.to_f > 0)
        raise ValidationError, "Amount must be greater than zero"
      end

      raise ValidationError, "Due date is required" if @due_date.nil?

      if @due_date < @purchase_date
        raise ValidationError, "Due date cannot be before purchase date"
      end
    end

    # A row counts only with a product and a positive quantity; anything else
    # is an unfinished row the form left behind.
    def complete_items
      @items.select { |item| item[:product_id].present? && item[:quantity].to_i.positive? }
    end

    def lines
      @lines ||= complete_items.map do |item|
        Line.new(product: find_product(item[:product_id]),
                 quantity: item[:quantity].to_i,
                 unit_cost: unit_cost_from(item[:unit_cost]))
      end
    end

    def find_product(id)
      Product.find_by(id: id) || raise(ValidationError, "Product not found: #{id}")
    end

    # A blank cost is a free line; a nil one is an amount the controller could
    # not read, and a free line by accident is exactly what must not happen.
    def unit_cost_from(raw)
      raise ValidationError, "Unit cost is not a number" if raw.nil?
      return BigDecimal("0") if raw.to_s.strip.empty?

      cost = BigDecimal(raw.to_s)
      raise ValidationError, "Unit cost cannot be negative" if cost.negative?

      cost
    rescue ArgumentError
      raise ValidationError, "Unit cost is not a number"
    end

    def computed_amount
      lines.sum { |line| line.quantity * line.unit_cost }
    end

    def build_invoice
      @invoice = Invoice.new(
        supplier: @supplier,
        invoice_number: @invoice_number,
        amount: lines.any? ? computed_amount : @amount,
        currency: @currency,
        exchange_rate: @exchange_rate,
        purchase_date: @purchase_date,
        due_date: @due_date,
        status: "pending",
        has_items: false,
        notes: @notes,
        early_payment_due_date: @early_payment_due_date,
        early_payment_discount_percentage: @early_payment_discount_percentage
      )
    end

    # Built, not created: the amount guard on Invoice reads the lines in
    # memory to know the amount may be zero.
    def build_lines
      lines.each do |line|
        @invoice.invoice_items.build(product: line.product, quantity: line.quantity, unit_cost: line.unit_cost)
      end
    end

    def move_stock
      return if lines.empty?

      location = StockLocation.first!
      lines.each do |line|
        result = Inventory::AdjustStock.call(
          product: line.product,
          stock_location: location,
          movement_type: "purchase",
          quantity: line.quantity,
          reference: @invoice,
          note: "Factura #{@invoice_number}"
        )
        raise ValidationError, result.errors.join(", ") if result.failure?
      end
    end
  end
end
