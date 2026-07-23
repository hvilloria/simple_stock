# frozen_string_literal: true

module Sales
  # Replaces the product and/or quantity of an undelivered line on an
  # on_account order. When the product changes, the line takes the catalog
  # price; a quantity-only edit keeps the original line price.
  class ReplaceOrderItem
    def self.call(order_item:, product_id:, quantity:)
      new(order_item: order_item, product_id: product_id, quantity: quantity).call
    end

    def initialize(order_item:, product_id:, quantity:)
      @order_item = order_item
      @order      = order_item.order
      @product_id = product_id.to_i
      @quantity   = quantity.to_i
    end

    def call
      validate!

      # old_subtotal reads @order_item's pre-swap quantity/unit_price, so price
      # and delta must be captured before @order_item.update! changes them.
      price = new_price
      amount_delta = delta

      ActiveRecord::Base.transaction do
        @order_item.update!(product_id: @product_id, quantity: @quantity, unit_price: price)
        # Delta on BOTH totals: re-summing items would wipe the effective
        # discounts already subtracted from total_amount by CollectOnAccount.
        @order.update!(
          total_amount:          @order.total_amount + amount_delta,
          original_total_amount: @order.original_total_amount + amount_delta
        )
        @order.refresh_status_from_balance!
      end

      Result.new(success?: true, record: @order_item, errors: [])
    rescue ValidationError => e
      Result.new(success?: false, record: nil, errors: [ e.message ])
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, record: nil, errors: e.record.errors.full_messages)
    rescue StandardError => e
      Rails.logger.error("Error in Sales::ReplaceOrderItem: #{e.message}")
      Result.new(success?: false, record: nil, errors: [ "Error actualizando el producto" ])
    end

    private

    class ValidationError < StandardError; end

    def validate!
      unless @order.on_account_order_type? && !@order.cancelled_status?
        raise ValidationError, "La operación no es un pago a cuenta activo"
      end

      raise ValidationError, "El producto ya fue entregado" if @order_item.delivered_at.present?
      raise ValidationError, "La cantidad debe ser mayor a cero" if @quantity <= 0

      if product_changed?
        raise ValidationError, "Producto inválido" if new_product.nil?
        unless new_product.price_unit.to_d.positive?
          raise ValidationError, "El producto no tiene precio de catálogo — cargalo en Productos"
        end
      end

      projected_total = @order.total_amount + delta
      if projected_total < 0
        raise ValidationError, "El cambio dejaría la operación con un total negativo"
      elsif projected_total.zero? && !@order.from_paper?
        raise ValidationError, "El cambio dejaría la operación con un total en cero"
      end
    end

    def product_changed?
      @product_id != @order_item.product_id
    end

    def new_product
      @new_product ||= Product.active.find_by(id: @product_id)
    end

    def old_subtotal
      @old_subtotal ||= @order_item.quantity * @order_item.unit_price
    end

    def new_price
      @new_price ||= product_changed? ? new_product.price_unit : @order_item.unit_price
    end

    def delta
      @delta ||= (@quantity * new_price) - old_subtotal
    end
  end
end
