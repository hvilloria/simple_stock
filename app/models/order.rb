class Order < ApplicationRecord
  # Associations
  belongs_to :customer, optional: true
  has_many :order_items, dependent: :destroy
  has_many :stock_movements, as: :reference, dependent: :nullify

  # Enums
  enum :status, {
    confirmed: "confirmed",
    cancelled: "cancelled"
  }, suffix: true

  enum :order_type, {
    cash: "cash",
    credit: "credit"
  }, suffix: true

  # Constants
  ALLOWED_CHANNELS = %w[counter whatsapp mercadolibre].freeze

  # Validations
  validates :order_type, presence: true
  validates :total_amount, numericality: { greater_than: 0 }
  validates :channel, inclusion: { in: ALLOWED_CHANNELS, allow_nil: true }
  validate :credit_order_requires_credit_account

  # Scopes
  scope :cash, -> { where(order_type: "cash") }
  scope :credit, -> { where(order_type: "credit") }
  scope :active, -> { where.not(status: "cancelled") }

  def calculate_total!
    update!(total_amount: order_items.sum("quantity * unit_price"))
  end

  def cancel!(reason: nil)
    result = Sales::CancelOrder.call(order: self, reason: reason)

    if result.success?
      result.record
    else
      raise StandardError, result.errors.join(", ")
    end
  end

  private

  # Valida que las ventas a crédito solo se hagan a clientes con cuenta corriente
  def credit_order_requires_credit_account
    return unless credit_order_type?
    return if customer.nil? # Ya se maneja con belongs_to optional

    unless customer.has_credit_account?
      errors.add(:base, "Credit orders require a customer with credit account enabled")
    end
  end
end
