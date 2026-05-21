module Sales
  # Sales::CreateOrder
  #
  # Crea órdenes de venta + pagos asociados en una sola transacción.
  #
  # Modos:
  #   - LIVE (default): precios desde la BD, valida stock disponible
  #   - FROM_PAPER:     unit_price puede ser nil, total puede ser 0,
  #                     requiere paper_number, no valida stock
  #
  # Pagos (`payments:` array de `{ amount:, payment_method: }`):
  #   - immediate: OBLIGATORIO, sum(amount) == total_amount (tolerancia 0.01)
  #   - credit:    OPCIONAL, sum(amount) <= total_amount
  #
  # Cada entrada produce un Payment + PaymentAllocation apuntando a la orden.
  class CreateOrder
    Item = Struct.new(:product_id, :quantity, :unit_price, keyword_init: true)
    PAYMENT_SUM_TOLERANCE = 0.01

    def self.call(customer:, items:, order_type:, channel: nil, source: "live",
                  sale_date: nil, paper_number: nil, payments: [], discount_percent: 0)
      new(
        customer: customer,
        items: items,
        order_type: order_type,
        channel: channel,
        source: source,
        sale_date: sale_date,
        paper_number: paper_number,
        payments: payments,
        discount_percent: discount_percent
      ).call
    end

    def initialize(customer:, items:, order_type:, channel: nil, source: "live",
                   sale_date: nil, paper_number: nil, payments: [], discount_percent: 0)
      @customer = customer
      @items = items.map { |item| item.is_a?(Item) ? item : Item.new(item) }
      @order_type = order_type
      @channel = channel
      @source = source
      @sale_date = sale_date || Date.today
      @paper_number = paper_number
      @payments_data = normalize_payments(payments)
      @discount_percent = discount_percent.to_d
    end

    def call
      validate_params

      ActiveRecord::Base.transaction do
        create_order
        create_order_items
        create_payments if @payments_data.any?

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

    def normalize_payments(payments)
      Array(payments).filter_map do |entry|
        h = entry.to_h.symbolize_keys
        amount = h[:amount].to_f
        next if amount <= 0
        { amount: amount, payment_method: h[:payment_method] }
      end
    end

    def validate_params
      unless %w[immediate credit].include?(@order_type)
        raise ValidationError, "Invalid order type"
      end

      raise ValidationError, "Customer is required" if @customer.nil?

      if @order_type == "credit" && !@customer.has_credit_account?
        raise ValidationError, "Customer does not have credit account enabled"
      end

      raise ValidationError, "At least one product is required" if @items.blank?

      @items.each do |item|
        raise ValidationError, "Product ID is required" unless item.product_id
        raise ValidationError, "Quantity must be greater than zero" unless item.quantity.to_i > 0
      end

      unless @source == "from_paper"
        @items.each do |item|
          product = Product.find(item.product_id)
          if product.current_stock < item.quantity
            raise ValidationError, "Insufficient stock for #{product.name}. Available: #{product.current_stock}"
          end
        end
      end

      validate_discount
      validate_payments
    end

    def validate_discount
      return if @discount_percent.zero?

      if @order_type == "credit"
        raise ValidationError, "No se permite descuento en ventas a crédito"
      end

      if @order_type == "immediate" && @discount_percent > 10
        raise ValidationError, "Descuento máximo permitido en ventas inmediatas: 10%"
      end
    end

    def validate_payments
      @payments_data.each do |entry|
        unless Payment::PAYMENT_METHODS.include?(entry[:payment_method])
          raise ValidationError, "Método de pago inválido: #{entry[:payment_method]}"
        end
      end

      # from_paper orders cargan ventas históricas — no validamos pagos.
      return if @source == "from_paper"

      total = calculate_total
      paid_sum = @payments_data.sum { |e| e[:amount] }

      case @order_type
      when "immediate"
        if @payments_data.empty?
          raise ValidationError, "El pago es requerido para ventas de contado"
        end
        if (paid_sum - total).abs > PAYMENT_SUM_TOLERANCE
          raise ValidationError, "La suma de los pagos ($#{paid_sum}) debe coincidir con el total de la venta ($#{total})"
        end
      when "credit"
        if paid_sum > total + PAYMENT_SUM_TOLERANCE
          raise ValidationError, "El monto cobrado no puede exceder el total de la venta ($#{total})"
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
        total_amount: calculate_total,
        original_total_amount: original_total
      )
    end

    def calculate_total
      @calculate_total ||= (original_total * (1 - @discount_percent / 100)).round(2)
    end

    def original_total
      @original_total ||= @items.sum do |item|
        product = Product.find(item.product_id)
        unit_price = item.unit_price || product.price_unit || 0
        item.quantity * unit_price
      end
    end

    def create_order_items
      @items.each do |item|
        product = Product.find(item.product_id)
        final_price = item.unit_price || product.price_unit || 0

        OrderItem.create!(
          order: @order,
          product: product,
          quantity: item.quantity,
          unit_price: final_price,
          discount_percent: @discount_percent
        )
      end
    end

    def create_payments
      @payments_data.each do |entry|
        payment = Payment.create!(
          customer:       @customer,
          amount:         entry[:amount],
          payment_method: entry[:payment_method],
          payment_date:   @sale_date
        )
        PaymentAllocation.create!(
          payment: payment,
          order:   @order,
          amount:  entry[:amount]
        )
      end
    end
  end
end
