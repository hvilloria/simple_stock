class OrderItem < ApplicationRecord
  belongs_to :order
  belongs_to :product

  validates :quantity, numericality: { greater_than: 0 }
  # unit_price may be NULL in sales-lite mode
  # If it is NULL, it is treated as 0 in the calculations
  validates :unit_price,
            numericality: { greater_than_or_equal_to: 0 },
            allow_nil: true
  validates :discount_percent,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 20 }
  validate :discount_within_order_type_cap

  private

  def discount_within_order_type_cap
    return if order.nil? || discount_percent.nil? || discount_percent.zero?

    if order.immediate_order_type? && discount_percent > 10
      errors.add(:discount_percent, "no puede exceder 10% en ventas inmediatas")
    end
  end
end
