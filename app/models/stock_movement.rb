class StockMovement < ApplicationRecord
  # Associations
  belongs_to :product
  belongs_to :stock_location
  belongs_to :reference, polymorphic: true, optional: true

  # Enums
  enum :movement_type, {
    purchase: "purchase",
    sale: "sale",
    adjustment: "adjustment"
  }, suffix: true

  # Validations
  validates :quantity, presence: true
  validates :movement_type, presence: true
  validates :stock_location, presence: true
  validates :reference_type, inclusion: { in: %w[Order Invoice] }, if: -> { reference_id.present? }

  def inbound?
    quantity.positive?
  end

  def outbound?
    quantity.negative?
  end
end
