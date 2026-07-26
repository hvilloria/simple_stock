# frozen_string_literal: true

class CreditNote < ApplicationRecord
  # Associations
  belongs_to :supplier
  belongs_to :invoice, optional: true  # kept temporarily; column will be dropped after data migration
  has_many :credit_note_items, dependent: :destroy
  has_many :products, through: :credit_note_items
  has_many :applied_credits, dependent: :destroy

  # Enums
  # active:    available credit, may have been partially applied
  # cancelled: voided, not available for use
  # exhausted is derived: active_status? && remaining_balance == 0
  enum status: {
    active: "active",
    cancelled: "cancelled"
  }, _suffix: true

  # Ensure new records always have a valid status (DB default was stale "pending" from old schema)
  after_initialize { self.status ||= :active }

  # Validations
  validates :credit_note_number, presence: true, uniqueness: true
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :currency, inclusion: { in: %w[USD ARS] }
  validates :exchange_rate, presence: true, if: :usd_currency?
  validates :exchange_rate, numericality: { greater_than: 0 }, allow_nil: true
  validates :issue_date, presence: true
  validates :supplier_id, presence: true

  # Scopes
  scope :for_supplier, ->(supplier) { where(supplier_id: supplier.id) if supplier.present? }
  scope :search_number, ->(query) { where("credit_note_number ILIKE ?", "%#{query}%") if query.present? }
  scope :recent, -> { order(issue_date: :desc, created_at: :desc, id: :desc) }
  scope :available, -> { where(status: "active") }

  APPLIED_SUM = "COALESCE((SELECT SUM(ac.amount) FROM applied_credits ac WHERE ac.credit_note_id = credit_notes.id), 0)"

  scope :with_balance, -> { where("credit_notes.amount > #{APPLIED_SUM}") }
  scope :exhausted_credits, -> { where("credit_notes.amount <= #{APPLIED_SUM}") }

  scope :by_availability, ->(filter) {
    case filter
    when "available" then where(status: "active").with_balance
    when "applied"   then where(status: "active").exhausted_credits
    when "cancelled" then where(status: "cancelled")
    end
  }

  # Callbacks
  before_validation :set_currency_from_invoice, if: -> { invoice_id.present? && invoice_id_changed? }

  # === BALANCE METHODS ===

  # Amount remaining after all partial applications
  def remaining_balance
    amount - applied_credits.sum(&:amount)
  end

  # True when all credit has been consumed
  def exhausted?
    remaining_balance <= 0
  end

  # True when credit is active and still has balance to apply
  def available?
    active_status? && !exhausted?
  end

  # === AMOUNT METHODS ===

  def total_amount_ars
    if currency == "USD"
      amount * (exchange_rate || 0)
    else
      amount || 0
    end
  end

  def remaining_balance_ars
    if currency == "USD"
      remaining_balance * (exchange_rate || 0)
    else
      remaining_balance
    end
  end

  def has_items?
    credit_note_items.any?
  end

  private

  def usd_currency?
    currency == "USD"
  end

  def set_currency_from_invoice
    return unless invoice

    self.currency = invoice.currency
    self.exchange_rate = invoice.exchange_rate
  end
end
