module Sales
  # Sales::CreateOrder
  #
  # Service para crear órdenes de venta.
  #
  # Soporta dos modos:
  # 1. LIVE (default): Venta en tiempo real con precios de BD
  # 2. FROM_PAPER: Venta cargada desde talonario físico
  #    - Permite unit_price nil (se trata como 0)
  #    - Permite total_amount = 0
  #    - Requiere paper_number para cruzar con talonario físico
  #
  # En ambos modos:
  # - Valida stock disponible
  # - Crea stock_movements de salida
  # - Actualiza current_stock de productos
  class CreateOrder
    # Estructura para representar un item de la venta
    Item = Struct.new(:product_id, :quantity, :unit_price, keyword_init: true)

    def self.call(customer:, items:, order_type:, channel: nil, source: "live", sale_date: nil, paper_number: nil)
      new(customer: customer, items: items, order_type: order_type, channel: channel, source: source, sale_date: sale_date, paper_number: paper_number).call
    end

    def initialize(customer:, items:, order_type:, channel: nil, source: "live", sale_date: nil, paper_number: nil)
      @customer = customer
      @items = items.map { |item| item.is_a?(Item) ? item : Item.new(item) }
      @order_type = order_type
      @channel = channel
      @source = source
      @sale_date = sale_date || Date.today
      @paper_number = paper_number
    end

    def call
      validate_params

      ActiveRecord::Base.transaction do
        create_order
        create_order_items
        create_stock_movements

        Result.new(success?: true, record: @order, errors: [])
      end
    rescue ValidationError => e
      Result.new(success?: false, record: nil, errors: [ e.message ])
    rescue StandardError => e
      Rails.logger.error("Error in Sales::CreateOrder: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      Result.new(success?: false, record: nil, errors: [ "Error creating order" ])
    end

    private

    class ValidationError < StandardError; end

    def validate_params
      # Validar order_type
      unless %w[cash credit].include?(@order_type)
        raise ValidationError, "Invalid order type"
      end

      # Validar customer
      raise ValidationError, "Customer is required" if @customer.nil?

      # Si es credit, validar has_credit_account
      if @order_type == "credit" && !@customer.has_credit_account?
        raise ValidationError, "Customer does not have credit account enabled"
      end

      # Validar items
      raise ValidationError, "At least one product is required" if @items.blank?

      @items.each do |item|
        raise ValidationError, "Product ID is required" unless item.product_id
        raise ValidationError, "Quantity must be greater than zero" unless item.quantity.to_i > 0
      end

      # Validar stock ANTES de crear nada
      @items.each do |item|
        product = Product.find(item.product_id)
        if product.current_stock < item.quantity
          raise ValidationError, "Insufficient stock for #{product.name}. Available: #{product.current_stock}"
        end
      end
    end

    def create_order
      @order = Order.create!(
        customer: @customer,
        order_type: @order_type,
        channel: @channel,
        source: @source,
        sale_date: @sale_date,
        paper_number: @paper_number,
        status: "confirmed",
        total_amount: calculate_total
      )
    end

    def calculate_total
      @items.sum do |item|
        product = Product.find(item.product_id)
        # Si unit_price es nil, intentar usar el del producto, si no 0
        unit_price = item.unit_price || product.price_unit || 0
        item.quantity * unit_price
      end
    end

    def create_order_items
      @items.each do |item|
        product = Product.find(item.product_id)
        # Si unit_price es nil, usar el del producto o 0
        final_price = item.unit_price || product.price_unit || 0

        OrderItem.create!(
          order: @order,
          product: product,
          quantity: item.quantity,
          unit_price: final_price
        )
      end
    end

    def create_stock_movements
      stock_location = StockLocation.first!

      @order.order_items.each do |order_item|
        result = Inventory::AdjustStock.call(
          product: order_item.product,
          stock_location: stock_location,
          movement_type: "sale",
          quantity: -order_item.quantity,
          reference: @order,
          note: "Sale ##{@order.id}"
        )

        raise ValidationError, result.errors.join(", ") if result.failure?
      end
    end
  end
end
