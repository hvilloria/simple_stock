class OrderItem < ApplicationRecord
  belongs_to :order
  belongs_to :product

  validates :quantity, numericality: { greater_than: 0 }
  # unit_price puede ser NULL en modo ventas-lite
  # Si es NULL, se trata como 0 en los cálculos
  validates :unit_price,
            numericality: { greater_than_or_equal_to: 0 },
            allow_nil: true
end
