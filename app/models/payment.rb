# frozen_string_literal: true

class Payment < ApplicationRecord
  # Associations
  belongs_to :customer
  has_many :allocations, class_name: "PaymentAllocation", dependent: :destroy
  has_many :orders, through: :allocations

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

  # Scopes
  scope :by_customer, ->(customer) { where(customer: customer) }
  scope :recent, -> { order(payment_date: :desc, created_at: :desc) }
end
