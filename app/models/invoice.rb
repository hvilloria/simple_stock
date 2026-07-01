class Invoice < ApplicationRecord
  # Associations
  belongs_to :supplier
  has_many :invoice_items, dependent: :destroy
  has_many :products, through: :invoice_items
  has_many :stock_movements, as: :reference, dependent: :nullify
  has_many :credit_notes, dependent: :restrict_with_error
  has_many :applied_credits, dependent: :destroy

  # Enums - Expand states
  enum :status, {
    pending: "pending",     # Invoice pending payment (simple mode)
    paid: "paid",          # Invoice paid (simple mode)
    confirmed: "confirmed", # Purchase confirmed (full mode)
    cancelled: "cancelled"  # Cancelled
  }, suffix: true

  # === COMMON VALIDATIONS ===
  validates :currency, inclusion: { in: %w[USD ARS] }
  validates :exchange_rate, presence: true, if: :usd_currency?
  validates :exchange_rate, numericality: { greater_than: 0 }, allow_nil: true
  validates :purchase_date, presence: true
  validates :supplier_id, presence: true

  # === SIMPLE MODE VALIDATIONS (has_items: false) ===
  validates :invoice_number, presence: true, unless: :has_items?
  validates :due_date, presence: true, unless: :has_items?
  validates :amount, presence: true, unless: :has_items?
  validates :amount, numericality: { greater_than: 0 }, if: -> { !has_items? && amount.present? }

  # === FULL MODE VALIDATIONS (has_items: true) ===
  # Validate invoice_items only after creating the invoice (not during create)
  validates :invoice_items, presence: true, if: -> { has_items? && !new_record? }, on: :update

  # === CALLBACKS ===
  before_validation :set_early_payment_terms, on: :create, if: -> { supplier.present? && purchase_date.present? }

  # === SCOPES ===
  scope :simple_mode, -> { where(has_items: false) }
  scope :full_mode, -> { where(has_items: true) }
  scope :pending_payment, -> { where(status: "pending") }
  scope :paid_invoices, -> { where(status: "paid") }
  scope :overdue, -> { simple_mode.where(status: "pending").where("due_date < ?", Date.current) }
  scope :due_soon, -> { simple_mode.where(status: "pending").where("due_date <= ?", 7.days.from_now.to_date) }
  scope :by_due_date, -> { order(due_date: :asc) }

  # New scopes for metrics
  scope :due_today, -> { simple_mode.where(status: "pending").where(due_date: Date.current) }
  scope :due_this_week, -> {
    start_of_week = Date.current.beginning_of_week(:monday)
    end_of_week = Date.current.end_of_week(:monday)
    simple_mode.where(status: "pending").where(due_date: start_of_week..end_of_week)
  }

  scope :due_next_week, -> {
    start_of_week = (Date.current + 1.week).beginning_of_week(:monday)
    end_of_week = (Date.current + 1.week).end_of_week(:monday)
    simple_mode.where(status: "pending").where(due_date: start_of_week..end_of_week)
  }

  scope :due_this_month, -> {
    simple_mode.where(status: "pending").where(
      due_date: Date.current.beginning_of_month..Date.current.end_of_month
    )
  }

  # Early payment scopes
  scope :with_early_payment, -> { where.not(early_payment_due_date: nil) }
  scope :discount_available, -> {
    with_early_payment.where("early_payment_due_date >= ?", Date.current)
  }

  # Pending invoices whose due_date OR early_payment_due_date falls within the period
  scope :due_or_discount_in_period, ->(start_date, end_date) {
    base = simple_mode.where(status: "pending")
    base.where(due_date: start_date..end_date)
        .or(base.where(early_payment_due_date: start_date..end_date)
                .where("early_payment_due_date >= ?", Date.current))
  }

  # Filter by supplier (accepts nil for "all")
  scope :for_supplier, ->(supplier) { where(supplier_id: supplier.id) if supplier.present? }

  # Search by invoice number (case-insensitive, partial match)
  scope :search_invoice, ->(query) { where("invoice_number ILIKE ?", "%#{query}%") if query.present? }

  # Ordered by priority: 1) pending first, 2) nearest due date
  scope :priority_order, -> {
    order(
      Arel.sql("CASE WHEN status = 'pending' THEN 0 ELSE 1 END"),
      Arel.sql("CASE WHEN due_date IS NULL THEN 1 ELSE 0 END"),
      "due_date ASC"
    )
  }

  # === CLASS METHODS (for metrics) ===

  # Calculates the total pending amount in ARS, optionally filtered by supplier
  # @param supplier [Supplier, nil] Supplier to filter by, or nil for all
  # @return [Float] Total in ARS
  def self.total_pending_amount_ars(supplier: nil)
    scope = simple_mode.pending_payment
    scope = scope.for_supplier(supplier) if supplier
    scope.sum { |i| i.total_amount_ars }
  end

  # === SIMPLE MODE METHODS ===

  def simple_mode?
    !has_items?
  end

  def full_mode?
    has_items?
  end

  # Unified total (works for both modes)
  def total_amount
    if has_items?
      calculate_total  # Sum of items
    else
      amount  # Direct amount
    end
  end

  # Total in ARS (works for both modes)
  def total_amount_ars(include_discount: false)
    if currency == "USD"
      total_amount * (exchange_rate || 0)
    else
      include_discount ? amount_with_discount_ars : amount
    end
  end

  def overdue?
    pending_status? && due_date && due_date < Date.current
  end

  def days_until_due
    return nil unless due_date
    (due_date - Date.current).to_i
  end

  def mark_as_paid!(payment_date = Date.current, paid_with_discount: false)
    raise "Cannot mark as paid: not in simple mode" unless simple_mode?
    raise "Cannot mark as paid: already paid" if paid_status?

    update!(status: "paid", paid_at: payment_date, paid_with_discount: paid_with_discount)
  end

  # === APPLIED CREDITS METHODS ===

  # Total credits already applied to this invoice (ARS)
  def applied_credits_amount
    applied_credits.sum(:amount)
  end

  # Net amount still owed after credits (ARS)
  def net_amount
    total_amount_ars - applied_credits_amount
  end

  # === EARLY PAYMENT METHODS ===

  # Amount with discount applied
  def amount_with_discount
    return amount unless early_payment_discount_percentage.present?
    amount * (1 - (early_payment_discount_percentage / 100.0))
  end

  # Amount in ARS with discount
  def amount_with_discount_ars
    if currency == "USD"
      amount_with_discount * (exchange_rate || 0)
    else
      amount_with_discount || 0
    end
  end

  # Is it eligible for a discount on this date?
  def eligible_for_discount?(payment_date = Date.current)
    return false unless early_payment_due_date.present?
    payment_date <= early_payment_due_date
  end

  # Potential savings if paid with discount
  def potential_savings
    return 0 unless early_payment_due_date.present?
    amount - amount_with_discount
  end

  def potential_savings_ars
    if currency == "USD"
      potential_savings * (exchange_rate || 0)
    else
      potential_savings || 0
    end
  end

  # Days until the discount expires
  def days_until_discount_expires
    return nil unless early_payment_due_date.present?
    (early_payment_due_date - Date.current).to_i
  end

  # === FULL MODE METHODS (existing) ===

  # Calculate total cost from invoice items
  def calculate_total
    return amount unless has_items?
    invoice_items.sum { |item| item.quantity * item.unit_cost }
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

  def set_early_payment_terms
    return unless supplier.has_early_payment_discount?
    return if early_payment_due_date.present? || early_payment_discount_percentage.present?

    self.early_payment_due_date = purchase_date + supplier.early_payment_days.days
    self.early_payment_discount_percentage = supplier.early_payment_discount_percentage
  end
end
