class Supplier < ApplicationRecord
  # Associations
  has_many :invoices, dependent: :restrict_with_error
  has_many :credit_notes, dependent: :restrict_with_error

  # Validations
  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP, allow_blank: true }
  validates :payment_term_days, numericality: { only_integer: true, greater_than: 0, allow_nil: true }
  validates :early_payment_days, numericality: { only_integer: true, greater_than: 0, allow_nil: true }
  validates :early_payment_discount_percentage, numericality: { greater_than: 0, less_than_or_equal_to: 100, allow_nil: true }
  validates :early_payment_days, presence: true, if: -> { early_payment_discount_percentage.present? }
  validates :early_payment_discount_percentage, presence: true, if: -> { early_payment_days.present? }
  validate :expense_types_are_billable
  validate :payment_terms_only_for_suppliers

  before_validation :strip_blank_expense_types

  # Scopes
  scope :alphabetical, -> { order(:name) }
  scope :billing, ->(type) { where("? = ANY (suppliers.expense_types)", type.to_s) if Invoice::EXPENSE_TYPE_LABELS.key?(type.to_s) }

  # Helper methods
  def bills?(type)
    expense_types.include?(type.to_s)
  end

  def offers_payment_terms?
    bills?("supplier") || bills?("utilities")
  end

  def payment_terms_present?
    [ payment_term_days, early_payment_days, early_payment_discount_percentage ].any?(&:present?)
  end

  def bank_info_present?
    bank_alias.present? || bank_account.present?
  end

  def bank_info_formatted
    parts = []
    parts << "Alias: #{bank_alias}" if bank_alias.present?
    parts << "Cuenta: #{bank_account}" if bank_account.present?
    parts.join(" | ")
  end

  def total_pending_amount
    invoices.simple_mode.pending_payment.sum do |invoice|
      invoice.total_amount_ars
    end
  end

  def pending_invoices_count
    invoices.simple_mode.pending_payment.count
  end

  def expense_types_display
    expense_types.map { |key| Invoice.expense_type_label(key) }.join(" · ")
  end

  def payment_term_display
    payment_term_days ? "#{payment_term_days} días" : "No definido"
  end

  # Total credit available from active notes, accounting for partial applications.
  # Uses remaining_balance_ars to normalize USD notes to ARS equivalent.
  def total_credit_notes_amount
    credit_notes.where(status: "active").sum { |cn| cn.remaining_balance_ars }
  end

  def credit_notes_count
    # Only notes with available balance (excludes those already applied/exhausted)
    credit_notes.count(&:available?)
  end

  def current_balance
    total_pending_amount - total_credit_notes_amount
  end

  def has_early_payment_discount?
    early_payment_days.present? && early_payment_discount_percentage.present?
  end

  def early_payment_display
    return "No configurado" unless has_early_payment_discount?
    percentage = early_payment_discount_percentage.to_i == early_payment_discount_percentage ? early_payment_discount_percentage.to_i : early_payment_discount_percentage
    "#{percentage}% si paga en #{early_payment_days} días"
  end

  private

  def strip_blank_expense_types
    self.expense_types = Array(expense_types).map(&:to_s).compact_blank.uniq
  end

  def expense_types_are_billable
    if expense_types.empty?
      errors.add(:base, "Elegí al menos un tipo de factura")
    elsif (expense_types - Invoice::EXPENSE_TYPE_LABELS.keys).any?
      errors.add(:base, "Tipo de factura inválido")
    end
  end

  def payment_terms_only_for_suppliers
    return if offers_payment_terms? || !payment_terms_present?

    errors.add(:base, "Las condiciones de pago solo corresponden a proveedores o servicios")
  end
end
