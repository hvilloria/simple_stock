# frozen_string_literal: true

class PaymentAllocation < ApplicationRecord
  belongs_to :payment
  belongs_to :order

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validate :order_belongs_to_payment_customer
  validate :amount_within_order_outstanding_balance

  private

  def order_belongs_to_payment_customer
    return if payment.nil? || order.nil?

    if order.customer_id != payment.customer_id
      errors.add(:order, "no pertenece al cliente del pago")
    end
  end

  def amount_within_order_outstanding_balance
    return if amount.nil? || order.nil? || order.total_amount.nil?

    other_paid = PaymentAllocation
                   .where(order_id: order_id)
                   .where.not(id: id)
                   .sum(:amount)
    remaining = order.total_amount - other_paid

    if amount > remaining
      errors.add(:amount, "no puede exceder el saldo pendiente de la orden ($#{remaining})")
    end
  end
end
