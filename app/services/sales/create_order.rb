module Sales
  class CreateOrder
    Line = Struct.new(:product, :quantity, :unit_price, keyword_init: true)

    def self.call(customer: nil, lines:)
      new(customer: customer, lines: lines).call
    end

    def initialize(customer:, lines:)
      @customer = customer
      @lines    = lines.map do |line|
        line.is_a?(Line) ? line : Line.new(line)
      end
    end

    def call
      validate_params
      
      ActiveRecord::Base.transaction do
        create_order
        create_order_items
        adjust_stock
        
        @order.calculate_total!
        
        Result.new(success?: true, record: @order, errors: [])
      end
    rescue ValidationError => e
      Result.new(success?: false, record: nil, errors: [e.message])
    rescue StandardError => e
      Rails.logger.error("Error in Sales::CreateOrder: #{e.message}")
      Result.new(success?: false, record: nil, errors: ['Error creating order'])
    end

    private

    class ValidationError < StandardError; end

    def validate_params
      raise ValidationError, "Lines cannot be empty" if @lines.empty?

      @lines.each do |line|
        raise ValidationError, "Product is required" unless line.product
        raise ValidationError, "Quantity must be greater than zero" unless line.quantity.to_i > 0
      end
    end

    def create_order
      @order = Order.create!(
        customer:     @customer,
        status:       :confirmed,
        total_amount: 0
      )
    end

    def create_order_items
      @lines.each do |line|
        OrderItem.create!(
          order:      @order,
          product:    line.product,
          quantity:   line.quantity,
          unit_price: line.unit_price || line.product.price_unit
        )
      end
    end

    def adjust_stock
      stock_location = StockLocation.first!

      @lines.each do |line|
        result = Inventory::AdjustStock.call(
          product:        line.product,
          stock_location: stock_location,
          movement_type:  :sale,
          quantity:       -line.quantity.to_i,
          reference:      "ORDER-#{@order.id}",
          note:           "Sale #{@order.id}"
        )

        raise ValidationError, result.errors.join(", ") if result.failure?
      end
    end
  end
end
