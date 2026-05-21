class OrderItem < ApplicationRecord
  belongs_to :order
  belongs_to :product

  validates :quantity, numericality: { greater_than: 0 }
  # unit_price puede ser NULL en modo ventas-lite
  # Si es NULL, se trata como 0 en los cálculos
  validates :unit_price,
            numericality: { greater_than_or_equal_to: 0 },
            allow_nil: true
  validates :discount_percent,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 20 }
  validate :discount_within_order_type_cap

  private

  def discount_within_order_type_cap
    return if order.nil? || discount_percent.nil? || discount_percent.zero?

    if order.credit_order_type?
      errors.add(:discount_percent, "no se permite descuento en ventas a crédito")
    elsif order.immediate_order_type? && discount_percent > 10
      errors.add(:discount_percent, "no puede exceder 10% en ventas inmediatas")
    end
  end
end
