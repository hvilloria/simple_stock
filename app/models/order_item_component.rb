class OrderItemComponent < ApplicationRecord
  belongs_to :order_item
  belongs_to :product, -> { with_deleted }

  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
end
