# frozen_string_literal: true

class Payment < ApplicationRecord
  # Associations
  belongs_to :customer
  has_many :allocations, class_name: "PaymentAllocation", dependent: :destroy
  has_many :orders, through: :allocations
  has_many :cash_movements, -> { order(:id) }, foreign_key: :source_payment_id,
           inverse_of: :source_payment, dependent: nil

  # Constants
  # Official payment methods — single source of truth (labels + UI options).
  # See docs/decisiones/2026-06-26-metodos-de-pago.md.
  # `cash` is kept as the key: the "discount cash only" rule
  # (Payments::CollectSaleNote / CollectOnAccount) compares against "cash".
  PAYMENT_METHOD_LABELS = {
    "cash"          => "Efectivo",
    "bank_qr"       => "Banco QR",
    "bank_card"     => "Banco Tarjeta",
    "bank_transfer" => "Banco Transferencia",
    "mercado_pago"  => "Mercado Pago"
  }.freeze

  PAYMENT_METHODS = PAYMENT_METHOD_LABELS.keys.freeze
  MISSING_METHOD_ERROR = "No se puede guardar el cobro sin medio de pago"

  INVOICE_TYPE_LABELS = {
    "a"    => "Factura A",
    "b"    => "Factura B",
    "none" => "Sin factura"
  }.freeze

  enum :invoice_type, { a: "a", b: "b", none: "none" }, suffix: true

  def self.method_label(key)
    PAYMENT_METHOD_LABELS.fetch(key.to_s, key.to_s.humanize)
  end

  def self.method_options
    PAYMENT_METHOD_LABELS.map { |key, label| [ label, key ] }
  end

  # Validations
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :payment_method, presence: true, inclusion: { in: PAYMENT_METHODS }
  validates :payment_date, presence: true
  validate :invoice_number_matches_invoice_type

  # Scopes
  scope :by_customer, ->(customer) { where(customer: customer) }
  scope :recent, -> { order(payment_date: :desc, created_at: :desc) }

  def billed? = invoice_type.present?

  def invoice_label
    return nil unless billed?
    return INVOICE_TYPE_LABELS.fetch("none") if none_invoice_type?

    "#{INVOICE_TYPE_LABELS.fetch(invoice_type)} · #{invoice_number}"
  end

  def original_cash_movement = cash_movements.find(&:inflow?)
  def reversal_movement = cash_movements.find(&:reversal?)

  # Only cash may carry a discount or cash above the total; credit item
  # discounts are not cash-only.
  def cash_discounted?
    return false unless payment_method == "cash"

    allocations.any? { |a| a.discount_amount.positive? || a.overpaid_amount.positive? } ||
      orders.any? { |o| o.immediate_order_type? && o.discount_amount.positive? }
  end

  def method_change_block
    movement = original_cash_movement
    return :locked if movement.nil? || reversal_movement
    return :closed if movement.sealed? || DailyClosing.exists?(business_date: movement.business_date)
    return :cash_discount if cash_discounted?

    nil
  end

  private

  def invoice_number_matches_invoice_type
    if %w[a b].include?(invoice_type) && invoice_number.blank?
      errors.add(:invoice_number, "es obligatorio para facturas tipo A o B")
    elsif invoice_type == "none" && invoice_number.present?
      errors.add(:invoice_number, "debe estar vacío cuando no hay factura")
    elsif invoice_type.nil? && invoice_number.present?
      errors.add(:invoice_type, "debe indicarse antes de cargar un número de factura")
    end
  end
end
