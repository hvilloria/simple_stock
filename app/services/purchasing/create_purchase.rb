# frozen_string_literal: true

module Purchasing
  class CreatePurchase
    def self.call(supplier:, items:, currency:, exchange_rate: nil, purchase_date: nil, notes: nil)
      new(
        supplier: supplier,
        items: items,
        currency: currency,
        exchange_rate: exchange_rate,
        purchase_date: purchase_date,
        notes: notes
      ).call
    end

    def initialize(supplier:, items:, currency:, exchange_rate: nil, purchase_date: nil, notes: nil)
      @supplier = supplier
      @items = items # Array de { product_id:, quantity:, unit_cost: }
      @currency = currency
      @exchange_rate = exchange_rate
      @purchase_date = purchase_date || Date.today
      @notes = notes
    end

    def call
      validate_params

      ActiveRecord::Base.transaction do
        create_purchase
        create_purchase_items
        create_stock_movements
        recalculate_product_costs

        Result.new(success?: true, record: @purchase, errors: [])
      end
    rescue ValidationError => e
      Result.new(success?: false, record: nil, errors: [ e.message ])
    rescue StandardError => e
      Rails.logger.error("Error in Purchasing::CreatePurchase: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      Result.new(success?: false, record: nil, errors: [ "Error creating purchase" ])
    end

    private

    class ValidationError < StandardError; end

    def validate_params
      # Validar currency
      unless %w[USD ARS].include?(@currency)
        raise ValidationError, "Invalid currency. Must be USD or ARS"
      end

      # Si es USD, exchange_rate es obligatorio
      if @currency == "USD" && (@exchange_rate.nil? || @exchange_rate <= 0)
        raise ValidationError, "Exchange rate required for USD purchases"
      end

      # Validar supplier
      raise ValidationError, "Supplier is required" if @supplier.nil?

      # Validar items
      raise ValidationError, "At least one product is required" if @items.blank?

      @items.each do |item|
        raise ValidationError, "Product ID is required" unless item[:product_id]
        raise ValidationError, "Quantity must be greater than zero" unless item[:quantity].to_i > 0
        raise ValidationError, "Unit cost must be greater than or equal to zero" unless item[:unit_cost].to_f >= 0
      end

      # Validar que productos existan
      product_ids = @items.map { |i| i[:product_id] }
      found_ids = Product.where(id: product_ids).pluck(:id)
      missing_ids = product_ids - found_ids

      if missing_ids.any?
        raise ValidationError, "Products not found: #{missing_ids.join(', ')}"
      end
    end

    def create_purchase
      @purchase = Purchase.create!(
        supplier: @supplier,
        currency: @currency,
        exchange_rate: @exchange_rate,
        purchase_date: @purchase_date,
        status: "confirmed",
        total_cost: calculate_total,
        notes: @notes
      )
    end

    def calculate_total
      @items.sum do |item|
        item[:quantity].to_i * item[:unit_cost].to_f
      end
    end

    def create_purchase_items
      @items.each do |item|
        product = Product.find(item[:product_id])
        @purchase.purchase_items.create!(
          product: product,
          quantity: item[:quantity].to_i,
          unit_cost: item[:unit_cost].to_f
        )
      end
    end

    def create_stock_movements
      stock_location = StockLocation.first!

      @purchase.purchase_items.each do |purchase_item|
        result = Inventory::AdjustStock.call(
          product: purchase_item.product,
          stock_location: stock_location,
          movement_type: "purchase",
          quantity: purchase_item.quantity, # POSITIVO (entrada)
          reference: @purchase, # Polimórfico
          note: "Purchase ##{@purchase.id}"
        )

        raise ValidationError, result.errors.join(", ") if result.failure?
      end
    end

    def recalculate_product_costs
      @purchase.purchase_items.each do |item|
        item.product.recalculate_average_cost!
      end
    end
  end
end

