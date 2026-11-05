class ComboComponent < ApplicationRecord
  belongs_to :combo, class_name: "Product"
  belongs_to :product, -> { with_deleted }

  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :product_id, uniqueness: { scope: :combo_id }
end
