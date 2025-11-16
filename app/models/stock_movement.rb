class StockMovement < ApplicationRecord
  belongs_to :product
  belongs_to :stock_location

  enum :movement_type, {
    purchase: "purchase",
    sale: "sale",
    adjustment: "adjustment"
  }, suffix: true

  validates :quantity, presence: true
  validates :movement_type, presence: true
  validates :stock_location, presence: true


  def inbound?
    quantity.positive?
  end

  def outbound?
    quantity.negative?
  end
end
