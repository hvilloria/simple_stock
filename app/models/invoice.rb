class Invoice < ApplicationRecord
  # Associations
  belongs_to :supplier
  has_many :invoice_items, dependent: :destroy
  has_many :products, through: :invoice_items
  has_many :stock_movements, as: :reference, dependent: :nullify
  has_many :credit_notes, dependent: :restrict_with_error
  has_many :applied_credits, dependent: :destroy

  EXPENSE_TYPE_LABELS = {
    "supplier"       => "Proveedor",
    "taxes"          => "Impuestos",
    "utilities"      => "Servicios",
    "social_charges" => "Cargas sociales"
  }.freeze

  belongs_to :cash_movement, optional: true

  enum :expense_type, EXPENSE_TYPE_LABELS.keys.to_h { |k| [ k.to_sym, k ] }, suffix: true

  DETAIL_MAX_LENGTH = 40

  before_validation :normalize_identification
  before_save :clear_unused_fields

  validate :lines_only_on_supplier_invoices
  validate :non_supplier_identification, unless: :supplier_expense_type?
  validate :supplier_bills_expense_type, if: -> { new_record? || will_save_change_to_supplier_id? || will_save_change_to_expense_type? }

  scope :by_expense_type, ->(key) { where(expense_type: key) if EXPENSE_TYPE_LABELS.key?(key.to_s) }

  def self.expense_type_label(key) = EXPENSE_TYPE_LABELS.fetch(key.to_s, key.to_s)
  def self.expense_type_options = EXPENSE_TYPE_LABELS.map { |key, label| [ label, key ] }

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
  validates :invoice_number, presence: true, if: -> { supplier_expense_type? && !has_items? }
  validates :due_date, presence: true, unless: :has_items?
  validates :amount, presence: true, unless: :has_items?
  validates :amount, numericality: { greater_than: 0 }, if: -> { amount_required? && amount.present? }
  validates :amount, numericality: { greater_than_or_equal_to: 0 }, if: -> { !has_items? && !amount_required? && amount.present? }

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

  # Search by number, detail, period as MM/YYYY or the reference as shown (case-insensitive, partial match)
  scope :search_invoice, ->(query) {
    if query.present?
      pattern = "%#{sanitize_sql_like(query.to_s)}%"
      where("invoice_number ILIKE :q OR detail ILIKE :q OR to_char(period, 'MM/YYYY') ILIKE :q " \
            "OR concat_ws(' · ', detail, to_char(period, 'MM/YYYY')) ILIKE :q", q: pattern)
    end
  }

  # Filter by status, ignoring values outside the enum
  scope :by_status_filter, ->(status) { where(status: status) if statuses.key?(status.to_s) }

  # Ordered by payment date, most recent first
  scope :by_payment_date, -> { order(Arel.sql("paid_at DESC NULLS LAST"), id: :desc) }

  # Ordered by priority: 1) pending first, 2) nearest due date
  scope :priority_order, -> {
    order(
      Arel.sql("CASE WHEN status = 'pending' THEN 0 ELSE 1 END"),
      Arel.sql("CASE WHEN due_date IS NULL THEN 1 ELSE 0 END"),
      "due_date ASC",
      "id DESC"
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

  # What the operator calls this invoice: its number for a supplier, otherwise
  # the optional detail plus the period it covers.
  def reference
    build_reference(expense_type, invoice_number, detail, period)
  end

  # The reference as stored, whatever an unsaved edit has changed since.
  def reference_was
    build_reference(expense_type_in_database, invoice_number_in_database, detail_in_database, period_in_database)
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

  # The cash category an outflow paying this invoice is recorded under.
  def cash_category_attrs
    if supplier_expense_type?
      { category: "suppliers", subcategory: nil }
    else
      { category: "fixed_expense", subcategory: expense_type }
    end
  end

  # Pesos that leave the arca for this invoice on that date, before credits.
  def amount_due_ars(payment_date)
    due = eligible_for_discount?(payment_date) ? amount_with_discount_ars : total_amount_ars
    BigDecimal(due.to_s).round(2)
  end

  # True when a paid invoice left no cash movement because its credits covered
  # what it owed on the paid date (legacy invoices have no movement either, but
  # their credits only covered part of it).
  def paid_with_credits_only?
    return false unless paid_status? && paid_at && cash_movement_id.nil?

    credited = applied_credits.includes(:credit_note).sum do |applied|
      note = applied.credit_note
      note.currency == "USD" ? (applied.amount * note.exchange_rate.to_d).round(2) : applied.amount
    end
    credited.positive? && credited >= amount_due_ars(paid_at.to_date)
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

  def early_payment_applicable?
    supplier_expense_type? || utilities_expense_type?
  end

  private

  def lines_only_on_supplier_invoices
    return if supplier_expense_type? || invoice_items.empty?

    errors.add(:base, "Solo las facturas de proveedor llevan productos")
  end

  def normalize_identification
    self.detail = detail.to_s.strip.presence
    self.period = period&.beginning_of_month
  end

  # Only a supplier invoice has a number; every other type is told apart by its
  # period. Early-payment terms belong to supplier and utilities invoices only.
  # What a type does not use is dropped only once the save is going through, so
  # a refused edit re-renders with everything the user typed.
  def clear_unused_fields
    clear_early_payment_terms unless early_payment_applicable?

    if supplier_expense_type?
      self.period = nil
      self.detail = nil
    else
      self.invoice_number = nil
      self.exchange_rate = nil if currency == "ARS"
    end
  end

  def clear_early_payment_terms
    self.early_payment_due_date = nil
    self.early_payment_discount_percentage = nil
  end

  def build_reference(type, number, detail, period)
    return number if type == "supplier"

    [ detail.presence, period&.strftime("%m/%Y") ].compact.join(" · ")
  end

  def non_supplier_identification
    label = Invoice.expense_type_label(expense_type)
    errors.add(:base, "Falta el período") if period.nil?
    errors.add(:base, "El detalle no puede superar #{DETAIL_MAX_LENGTH} caracteres") if detail.to_s.length > DETAIL_MAX_LENGTH
    errors.add(:base, "Las boletas de #{label} son en pesos") unless currency == "ARS"
  end

  def supplier_bills_expense_type
    return if supplier.nil? || supplier.bills?(expense_type)

    errors.add(:base, "#{supplier.name} no factura #{Invoice.expense_type_label(expense_type)}")
  end

  # An amount-only invoice carries a typed amount that must be positive. An
  # invoice with lines takes its amount from them and may sum to zero.
  def amount_required?
    !has_items? && invoice_items.empty?
  end

  def usd_currency?
    currency == "USD"
  end

  def set_early_payment_terms
    return unless early_payment_applicable? && supplier.has_early_payment_discount?
    return if early_payment_due_date.present? || early_payment_discount_percentage.present?

    self.early_payment_due_date = purchase_date + supplier.early_payment_days.days
    self.early_payment_discount_percentage = supplier.early_payment_discount_percentage
  end
end
