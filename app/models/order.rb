class Order < ApplicationRecord
  belongs_to :customer, optional: true
  has_many :order_items, dependent: :destroy
  has_many :products, through: :order_items
  has_many :payment_allocations, dependent: :destroy
  has_many :payments, through: :payment_allocations
  has_many :stock_movements, as: :reference, dependent: :nullify

  accepts_nested_attributes_for :order_items, allow_destroy: true, reject_if: :all_blank

  enum :status, {
    pending:   "pending",
    confirmed: "confirmed",
    cancelled: "cancelled"
  }, suffix: true

  enum :order_type, {
    immediate: "immediate",
    credit:    "credit"
  }, suffix: true

  ALLOWED_CHANNELS = %w[counter whatsapp mercadolibre].freeze

  validates :order_type, presence: true
  validates :total_amount, numericality: { greater_than: 0 }, unless: :from_paper?
  validates :total_amount, numericality: { greater_than_or_equal_to: 0 }, if: :from_paper?
  validates :sale_date, presence: true
  validates :source, inclusion: { in: %w[live from_paper] }
  validates :channel, inclusion: { in: ALLOWED_CHANNELS, allow_nil: true }
  validates :paper_number, presence: true
  validate :credit_order_requires_credit_account
  validates :original_total_amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validate :original_total_at_least_current_total

  scope :immediate, -> { where(order_type: "immediate") }
  scope :credit,    -> { where(order_type: "credit") }
  scope :pending,   -> { where(status: "pending") }
  scope :confirmed, -> { where(status: "confirmed") }
  scope :active,    -> { where.not(status: "cancelled") }
  scope :from_paper, -> { where(source: "from_paper") }
  scope :live,       -> { where(source: "live") }
  scope :by_sale_date, ->(date) { where(sale_date: date) if date.present? }

  def outstanding_balance
    return 0 if cancelled_status?
    total_amount - payment_allocations.sum(:amount)
  end

  def from_paper?
    source == "from_paper"
  end

  def live?
    source == "live"
  end

  def calculate_total!
    update!(total_amount: order_items.sum("quantity * unit_price"))
  end

  def discount_amount
    return 0 if original_total_amount.nil? || total_amount.nil?
    original_total_amount - total_amount
  end

  def discount_percent_display
    order_items.first&.discount_percent.to_i
  end

  def refresh_status_from_balance!
    return if cancelled_status?
    new_status = outstanding_balance <= 0 ? "confirmed" : "pending"
    update!(status: new_status) if status != new_status
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

  def credit_order_requires_credit_account
    return unless credit_order_type?
    return if customer.nil?
    unless customer.has_credit_account?
      errors.add(:base, "Credit orders require a customer with credit account enabled")
    end
  end

  def original_total_at_least_current_total
    return if original_total_amount.nil? || total_amount.nil?
    if original_total_amount < total_amount
      errors.add(:original_total_amount, "no puede ser menor al total actual")
    end
  end
end
