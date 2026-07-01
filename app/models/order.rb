class Order < ApplicationRecord
  belongs_to :customer, optional: true
  belongs_to :user
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
    immediate:  "immediate",
    credit:     "credit",
    on_account: "on_account"
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
  validate :on_account_requires_contact
  validates :original_total_amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validate :original_total_at_least_current_total

  before_validation :normalize_contact_phone

  scope :immediate, -> { where(order_type: "immediate") }
  scope :credit,    -> { where(order_type: "credit") }
  scope :on_account, -> { where(order_type: "on_account") }

  scope :open_on_account, -> {
    on_account.active
      .left_joins(:order_items)
      .group("orders.id")
      .having(
        "orders.total_amount - " \
        "COALESCE((SELECT SUM(amount) FROM payment_allocations WHERE order_id = orders.id), 0) > 0 " \
        "OR COUNT(*) FILTER (WHERE order_items.delivered_at IS NULL) > 0"
      )
  }

  scope :search_contact, ->(q) {
    next all if q.blank?
    where("contact_name ILIKE :q OR contact_phone ILIKE :q", q: "%#{q.strip}%")
  }
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

  # Real NOMINAL discount (sum of the per-item discounts). It does NOT include the
  # ceil-to-100 rounding applied to the total to pay — that goes in #rounding_amount.
  def discount_amount
    order_items.sum { |i| (i.quantity * i.unit_price) * (i.discount_percent.to_d / 100) }.round(2)
  end

  # Ceil-to-100 rounding charge baked into total_amount (cash collection
  # with discount). 0 when there was no rounding (e.g. per-item credit discounts).
  def rounding_amount
    return 0 if total_amount.nil? || original_total_amount.nil?
    total_amount - (original_total_amount - discount_amount)
  end

  def discount_percent_display
    order_items.first&.discount_percent.to_i
  end

  def fully_delivered?
    order_items.where(delivered_at: nil).none?
  end

  def settled?
    outstanding_balance <= 0 && fully_delivered?
  end

  def delivered_items_count
    order_items.where.not(delivered_at: nil).count
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

  def normalize_contact_phone
    return if contact_phone.blank?
    self.contact_phone = contact_phone.gsub(/\D/, "")
  end

  def credit_order_requires_credit_account
    return unless credit_order_type?
    return if customer.nil?
    unless customer.has_credit_account?
      errors.add(:base, "Credit orders require a customer with credit account enabled")
    end
  end

  def on_account_requires_contact
    return unless on_account_order_type?
    errors.add(:contact_name, "es obligatorio para pagos a cuenta") if contact_name.blank?
    errors.add(:contact_phone, "es obligatorio para pagos a cuenta") if contact_phone.blank?
  end

  def original_total_at_least_current_total
    return if original_total_amount.nil? || total_amount.nil?
    if original_total_amount < total_amount
      errors.add(:original_total_amount, "no puede ser menor al total actual")
    end
  end
end
