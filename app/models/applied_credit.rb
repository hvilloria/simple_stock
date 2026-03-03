# frozen_string_literal: true

class AppliedCredit < ApplicationRecord
  # Associations
  belongs_to :credit_note
  belongs_to :invoice

  # Validations
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :applied_at, presence: true
  validate :amount_within_remaining_balance
  validate :same_supplier

  private

  def amount_within_remaining_balance
    return unless credit_note && amount

    already_applied = credit_note.applied_credits.where.not(id: id).sum(:amount)
    available = credit_note.amount - already_applied

    return unless amount > available

    errors.add(:amount, "supera el saldo disponible de la nota de crédito (disponible: #{available})")
  end

  def same_supplier
    return unless credit_note && invoice
    return if credit_note.supplier_id == invoice.supplier_id

    errors.add(:base, "La nota de crédito y la factura deben ser del mismo proveedor")
  end
end
