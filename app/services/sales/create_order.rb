module Sales
  # Sales::CreateOrder
  #
  # Creates a sale note (Order) in `pending` status. Vendor-facing entry point:
  # no payments, no discount, no stock movements (stock changes are not applied
  # at sale time today).
  #
  # Modes:
  #   - LIVE (default): prices from DB, validates stock availability
  #   - FROM_PAPER:     unit_price may be nil, total may be 0,
  #                     requires paper_number, no stock validation
  class CreateOrder
    Item = Struct.new(:product_id, :quantity, :unit_price, keyword_init: true)

    def self.call(customer:, items:, order_type:, paper_number:, channel: nil,
                  source: "live", sale_date: nil, contact_name: nil,
                  contact_phone: nil, delivered_product_ids: [])
      new(
        customer: customer,
        items: items,
        order_type: order_type,
        paper_number: paper_number,
        channel: channel,
        source: source,
        sale_date: sale_date,
        contact_name: contact_name,
        contact_phone: contact_phone,
        delivered_product_ids: delivered_product_ids
      ).call
    end

    def initialize(customer:, items:, order_type:, paper_number:, channel: nil,
                   source: "live", sale_date: nil, contact_name: nil,
                   contact_phone: nil, delivered_product_ids: [])
      @customer              = customer
      @items                 = items.map { |i| i.is_a?(Item) ? i : Item.new(i) }
      @order_type            = order_type
      @paper_number          = paper_number.presence
      @channel               = channel
      @source                = source
      @sale_date             = sale_date || Date.current
      @contact_name          = contact_name
      @contact_phone         = contact_phone
      @delivered_product_ids = Array(delivered_product_ids).map(&:to_i)
    end

    def call
      validate_params

      ActiveRecord::Base.transaction do
        create_order
        create_order_items
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
      unless %w[immediate credit on_account].include?(@order_type)
        raise ValidationError, "Invalid order type"
      end

      raise ValidationError, "Customer is required" if @customer.nil?
      raise ValidationError, "N° de talonario es requerido" if @paper_number.nil?

      if @order_type == "credit" && !@customer.has_credit_account?
        raise ValidationError, "Customer does not have credit account enabled"
      end

      if @order_type == "on_account" && (@contact_name.blank? || @contact_phone.blank?)
        raise ValidationError, "Nombre y teléfono de contacto son requeridos para pago a cuenta"
      end

      raise ValidationError, "At least one product is required" if @items.blank?

      @items.each do |item|
        raise ValidationError, "Product ID is required" unless item.product_id
        raise ValidationError, "Quantity must be greater than zero" unless item.quantity.to_i > 0
      end

      return if @source == "from_paper"

      @items.each do |item|
        product = Product.find(item.product_id)
        if product.current_stock < item.quantity
          raise ValidationError, "Insufficient stock for #{product.name}. Available: #{product.current_stock}"
        end
      end
    end

    def create_order
      total = calculate_total
      @order = Order.create!(
        customer:              @customer,
        order_type:            @order_type,
        channel:               @channel,
        source:                @source,
        sale_date:             @sale_date,
        paper_number:          @paper_number,
        status:                "pending",
        total_amount:          total,
        original_total_amount: total,
        contact_name:          @contact_name,
        contact_phone:         @contact_phone
      )
    end

    def calculate_total
      @calculate_total ||= @items.sum do |item|
        product    = Product.find(item.product_id)
        unit_price = item.unit_price || product.price_unit || 0
        item.quantity * unit_price
      end
    end

    def create_order_items
      @items.each do |item|
        product     = Product.find(item.product_id)
        final_price = item.unit_price || product.price_unit || 0

        OrderItem.create!(
          order:            @order,
          product:          product,
          quantity:         item.quantity,
          unit_price:       final_price,
          discount_percent: 0,
          delivered_at:     (@delivered_product_ids.include?(product.id) ? Time.current : nil)
        )
      end
    end
  end
end
