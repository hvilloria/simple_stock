class Purchase < ApplicationRecord
  # Associations
  belongs_to :supplier
  has_many :purchase_items, dependent: :destroy
  has_many :products, through: :purchase_items
  has_many :stock_movements, as: :reference, dependent: :nullify

  # Enums
  enum :status, {
    confirmed: "confirmed",
    cancelled: "cancelled"
  }, suffix: true

  # Validations
  validates :currency, inclusion: { in: %w[USD ARS] }
  validates :exchange_rate, presence: true, if: :usd_currency?
  validates :exchange_rate, numericality: { greater_than: 0 }, allow_nil: true
  validates :purchase_date, presence: true

  # Calculate total cost from purchase items
  def calculate_total
    purchase_items.sum { |item| item.quantity * item.unit_cost }
  end

  # Calculate total cost in ARS
  def calculate_total_ars
    if currency == "USD"
      calculate_total * exchange_rate
    else
      calculate_total
    end
  end

  private

  def usd_currency?
    currency == "USD"
  end
end
