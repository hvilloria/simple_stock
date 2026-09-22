module Sales
  # Sales::CreateOrder
  #
  # Creates a sale note (Order) in `pending` status. Vendor-facing entry point:
  # no payments, no discount. The goods leave the shelf with the note for an
  # immediate or credit sale; an on_account line leaves only when delivered.
  #
  # unit_price must be > 0. The entered price is written back to
  # product.price_unit inside the transaction.
  class CreateOrder
    Item = Struct.new(:product_id, :quantity, :unit_price, keyword_init: true)

    def self.call(customer:, items:, order_type:, paper_number:, user:,
                  channel: nil, source: "live", sale_date: nil,
                  contact_name: nil, contact_phone: nil,
                  delivered_product_ids: [])
      new(
        customer: customer,
        items: items,
        order_type: order_type,
        paper_number: paper_number,
        user: user,
        channel: channel,
        source: source,
        sale_date: sale_date,
        contact_name: contact_name,
        contact_phone: contact_phone,
        delivered_product_ids: delivered_product_ids
      ).call
    end

    def initialize(customer:, items:, order_type:, paper_number:, user:,
                   channel: nil, source: "live", sale_date: nil,
                   contact_name: nil, contact_phone: nil,
                   delivered_product_ids: [])
      @customer              = customer
      @items                 = items.map { |i| i.is_a?(Item) ? i : Item.new(i) }
      @order_type            = order_type
      @paper_number          = paper_number.presence
      @user                  = user
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
        raise ValidationError, "El precio debe ser mayor a cero" unless item.unit_price.to_f > 0
      end
    end

    def create_order
      total = calculate_total
      @order = Order.create!(
        customer:              @customer,
        user:                  @user,
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
      @calculate_total ||= @items.sum { |item| item.quantity * item.unit_price }
    end

    def create_order_items
      @items.each do |item|
        product     = Product.find(item.product_id)
        final_price = item.unit_price

        order_item = OrderItem.create!(
          order:            @order,
          product:          product,
          quantity:         item.quantity,
          unit_price:       final_price,
          discount_percent: 0,
          delivered_at:     (@delivered_product_ids.include?(product.id) ? Time.current : nil)
        )

        product.update!(price_unit: final_price)
        take_from_shelf(order_item) if leaves_the_shelf?(order_item)
      end
    end

    # An immediate or credit sale hands the goods over with the note; an
    # on_account line leaves the shelf only when it is delivered.
    def leaves_the_shelf?(order_item)
      @order_type != "on_account" || order_item.delivered_at.present?
    end

    def take_from_shelf(order_item)
      result = Inventory::DeductLineStock.call(order_item: order_item, note: "Nota #{@paper_number}")
      raise ValidationError, result.errors.join(", ") if result.failure?
    end
  end
end
