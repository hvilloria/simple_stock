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
      raise ArgumentError, "lines cannot be empty" if @lines.empty?

      ActiveRecord::Base.transaction do
        order = Order.create!(
          customer:     @customer,
          status:       :confirmed,
          total_amount: 0
        )

        stock_location = StockLocation.first!

        @lines.each do |line|
          raise ArgumentError, "product required"  unless line.product
          raise ArgumentError, "quantity must be > 0" unless line.quantity.to_i > 0

          OrderItem.create!(
            order:      order,
            product:    line.product,
            quantity:   line.quantity,
            unit_price: line.unit_price || line.product.price_unit
          )

          Inventory::AdjustStock.call(
            product:        line.product,
            stock_location: stock_location,
            movement_type:  :sale,
            quantity:       -line.quantity.to_i,
            reference:      "ORDER-#{order.id}",
            note:           "Venta #{order.id}"
          )
        end

        order.calculate_total!
        order
      end
    end
  end
end
