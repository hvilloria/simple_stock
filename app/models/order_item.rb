class OrderItem < ApplicationRecord
  belongs_to :order
  belongs_to :product, -> { with_deleted }
  has_many :stock_movements, as: :reference, dependent: :nullify
  has_many :components, class_name: "OrderItemComponent", dependent: :destroy

  validates :quantity, numericality: { greater_than: 0 }
  # unit_price may be NULL in sales-lite mode
  # If it is NULL, it is treated as 0 in the calculations
  validates :unit_price,
            numericality: { greater_than_or_equal_to: 0 },
            allow_nil: true
  validates :discount_percent,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 20 }
  validate :discount_within_order_type_cap

  # Quantities to move per product: the line itself, or each snapshot component times the line quantity.
  def stock_lines
    return [ [ product_id, quantity ] ] unless product.combo?

    components.sort_by(&:product_id).map { |component| [ component.product_id, component.quantity * quantity ] }
  end

  def unit_cost_in_ars
    return product.cost_in_ars unless product.combo?

    components.sum { |component| component.product.cost_in_ars * component.quantity }
  end

  private

  def discount_within_order_type_cap
    return if order.nil? || discount_percent.nil? || discount_percent.zero?

    if order.immediate_order_type? && discount_percent > 10
      errors.add(:discount_percent, "no puede exceder 10% en ventas inmediatas")
    end
  end
end
