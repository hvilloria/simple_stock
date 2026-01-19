# frozen_string_literal: true

class CreditNote < ApplicationRecord
  # Associations
  belongs_to :supplier
  belongs_to :invoice, optional: true
  has_many :credit_note_items, dependent: :destroy
  has_many :products, through: :credit_note_items

  # Enums
  enum status: {
    pending: "pending",      # Disponible para usar
    applied: "applied",      # Ya consumida/aplicada
    cancelled: "cancelled"   # Anulada
  }, _suffix: true

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
  scope :recent, -> { order(issue_date: :desc, created_at: :desc) }
  scope :available, -> { where(status: "pending") }
  scope :by_status, ->(status) { where(status: status) if status.present? }

  # Callbacks
  before_validation :set_currency_from_invoice, if: -> { invoice_id.present? && invoice_id_changed? }

  # Methods
  def total_amount_ars
    if currency == "USD"
      amount * (exchange_rate || 0)
    else
      amount || 0
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
