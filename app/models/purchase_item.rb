class PurchaseItem < ApplicationRecord
  # Associations
  belongs_to :purchase
  belongs_to :product

  # Validations
  validates :quantity, numericality: { greater_than: 0 }
  validates :unit_cost, numericality: { greater_than_or_equal_to: 0 }

  # Calculate unit cost in ARS
  def unit_cost_ars
    if purchase.currency == "USD"
      unit_cost * purchase.exchange_rate
    else
      unit_cost
    end
  end

  # Calculate subtotal in original currency
  def subtotal
    quantity * unit_cost
  end

  # Calculate subtotal in ARS
  def subtotal_ars
    quantity * unit_cost_ars
  end
end
