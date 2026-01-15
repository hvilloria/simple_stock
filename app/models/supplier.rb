class Supplier < ApplicationRecord
  # Associations
  has_many :purchases, dependent: :restrict_with_error

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
    purchases.simple_mode.pending_payment.sum do |purchase|
      purchase.total_amount_ars
    end
  end

  def pending_purchases_count
    purchases.simple_mode.pending_payment.count
  end

  def payment_term_display
    payment_term_days ? "#{payment_term_days} días" : "No definido"
  end
end
