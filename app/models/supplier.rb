class Supplier < ApplicationRecord
  # Associations
  has_many :invoices, dependent: :restrict_with_error
  has_many :credit_notes, dependent: :restrict_with_error

  # Validations
  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP, allow_blank: true }
  validates :payment_term_days, numericality: { only_integer: true, greater_than: 0, allow_nil: true }

  # Scopes
  scope :alphabetical, -> { order(:name) }

  # Métodos helper
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

  def payment_term_display
    payment_term_days ? "#{payment_term_days} días" : "No definido"
  end

  def total_credit_notes_amount
    credit_notes.available.sum { |cn| cn.total_amount_ars }
  end

  def credit_notes_count
    credit_notes.available.count
  end

  def current_balance
    total_pending_amount - total_credit_notes_amount
  end
end
