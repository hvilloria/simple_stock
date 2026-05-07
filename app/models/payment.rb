# frozen_string_literal: true

class Payment < ApplicationRecord
  # Associations
  belongs_to :customer
  belongs_to :order, optional: true

  # Constants
  PAYMENT_METHODS = %w[cash transfer check card].freeze

  # Validations
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :payment_method, presence: true, inclusion: { in: PAYMENT_METHODS }
  validates :payment_date, presence: true
  validate :customer_must_have_credit_account
  validate :amount_within_order_total, if: :order

  # Scopes
  scope :by_customer, ->(customer) { where(customer: customer) }
  scope :recent, -> { order(payment_date: :desc, created_at: :desc) }

  private

  def customer_must_have_credit_account
    return if customer.nil?

    unless customer.has_credit_account?
      errors.add(:customer, "must have credit account enabled")
    end
  end

  def amount_within_order_total
    return if amount.nil? || order.total_amount.nil?
    if amount > order.total_amount
      errors.add(:amount, "no puede exceder el total de la orden ($#{order.total_amount})")
    end
  end
end
