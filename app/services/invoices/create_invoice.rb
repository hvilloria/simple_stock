# frozen_string_literal: true

module Invoices
  # Registers an invoice. A supplier invoice may carry product lines, which it
  # stocks and takes its amount from; every other type (and a supplier invoice
  # without lines) is the amount-only invoice.
  class CreateInvoice
    Line = Struct.new(:product, :quantity, :unit_cost, keyword_init: true)

    def self.call(supplier:, amount:, currency:, invoice_number: nil,
                  exchange_rate: nil, purchase_date: nil, due_date:, notes: nil,
                  early_payment_due_date: nil, early_payment_discount_percentage: nil,
                  items: [], expense_type: "supplier", period: nil, detail: nil,
                  discount_percentage: nil, iva_percentage: nil)
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
        items: items,
        expense_type: expense_type,
        period: period,
        detail: detail,
        discount_percentage: discount_percentage,
        iva_percentage: iva_percentage
      ).call
    end

    def initialize(supplier:, amount:, currency:, invoice_number: nil,
                   exchange_rate: nil, purchase_date: nil, due_date:, notes: nil,
                   early_payment_due_date: nil, early_payment_discount_percentage: nil,
                   items: [], expense_type: "supplier", period: nil, detail: nil,
                   discount_percentage: nil, iva_percentage: nil)
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
      @expense_type = expense_type.to_s
      @period = period
      @detail = detail
      @discount_percentage = discount_percentage
      @iva_percentage = iva_percentage
    end

    def call
      validate_params

      ActiveRecord::Base.transaction do
        build_invoice
        build_lines
        @invoice.save!
        move_stock
        apply_costs

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
      raise ValidationError, "Tipo de factura inválido" unless Invoice::EXPENSE_TYPE_LABELS.key?(@expense_type)
      if @expense_type != "supplier" && lines.any?
        raise ValidationError, "Solo las facturas de proveedor llevan productos"
      end

      validate_identification
      validate_totals if lines.any?

      unless %w[USD ARS].include?(@currency)
        raise ValidationError, "Invalid currency. Must be USD or ARS"
      end

      if @currency == "USD" && (@exchange_rate.nil? || @exchange_rate <= 0)
        raise ValidationError, "Exchange rate required for USD invoices"
      end

      raise ValidationError, "Supplier is required" if @supplier.nil?

      if lines.empty? && !(@amount.to_f > 0)
        raise ValidationError, "Amount must be greater than zero"
      end

      raise ValidationError, "Due date is required" if @due_date.nil?

      if @due_date < @purchase_date
        raise ValidationError, "Due date cannot be before purchase date"
      end
    end

    # A supplier invoice is told apart by its number, every other type by the
    # period it covers (plus an optional detail), and it is always in pesos.
    def validate_identification
      if @expense_type == "supplier"
        raise ValidationError, "Invoice number is required" if @invoice_number.blank?
        return
      end

      raise ValidationError, "Falta el período" if @period.nil?
      if @detail.to_s.strip.length > Invoice::DETAIL_MAX_LENGTH
        raise ValidationError, "El detalle no puede superar #{Invoice::DETAIL_MAX_LENGTH} caracteres"
      end
      unless @currency == "ARS"
        raise ValidationError, "Las boletas de #{Invoice.expense_type_label(@expense_type)} son en pesos"
      end
    end

    # Product lines are bought in pesos, with the discount and IVA printed on
    # the paper: a blank discount is none, a blank IVA the general 21%.
    def validate_totals
      raise ValidationError, "Las facturas con productos se cargan en pesos" unless @currency == "ARS"

      @exchange_rate = nil
      @discount_percentage = percentage_from(@discount_percentage, 0, "El descuento debe estar entre 0 y 100")
      @iva_percentage = percentage_from(@iva_percentage, 21, "El IVA debe estar entre 0 y 100")
    end

    def percentage_from(raw, default, error)
      return BigDecimal(default) if raw.to_s.strip.empty?

      percentage = BigDecimal(raw.to_s)
      raise ValidationError, error unless percentage.between?(0, 100)

      percentage
    rescue ArgumentError
      raise ValidationError, error
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
      product = Product.find_by(id: id) || raise(ValidationError, "Product not found: #{id}")
      raise ValidationError, "Un combo no se puede comprar: cargar sus piezas" if product.combo?

      product
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

    def totals
      Totals.new(subtotal: lines.sum { |line| line.quantity * line.unit_cost },
                 discount_percentage: @discount_percentage, iva_percentage: @iva_percentage)
    end

    def final_unit_cost(line)
      Totals.final_unit_cost(line.unit_cost, discount_percentage: @discount_percentage, iva_percentage: @iva_percentage)
    end

    def build_invoice
      @invoice = Invoice.new(
        supplier: @supplier,
        invoice_number: @invoice_number,
        amount: lines.any? ? totals.total : @amount,
        currency: @currency,
        exchange_rate: @exchange_rate,
        purchase_date: @purchase_date,
        due_date: @due_date,
        status: "pending",
        has_items: false,
        expense_type: @expense_type,
        period: @period,
        detail: @detail,
        notes: @notes,
        early_payment_due_date: @early_payment_due_date,
        early_payment_discount_percentage: @early_payment_discount_percentage,
        discount_percentage: lines.any? ? @discount_percentage : nil,
        iva_percentage: lines.any? ? @iva_percentage : nil
      )
    end

    # Built, not created: the amount guard on Invoice reads the lines in
    # memory to know the amount may be zero.
    def build_lines
      lines.each do |line|
        @invoice.invoice_items.build(product: line.product, quantity: line.quantity, unit_cost: line.unit_cost,
                                     final_unit_cost: final_unit_cost(line))
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

    def apply_costs
      return if lines.empty?

      result = ApplyPurchaseCosts.call(invoice: @invoice)
      raise ValidationError, result.errors.join(", ") if result.failure?
    end
  end
end
