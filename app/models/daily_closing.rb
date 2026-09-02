# frozen_string_literal: true

class DailyClosing < ApplicationRecord
  belongs_to :user
  has_many :cash_movements, dependent: :restrict_with_exception

  validates :business_date, presence: true, uniqueness: true
  validates :expected_cash, presence: true, numericality: true
  validates :counted_cash, presence: true, numericality: true
  validates :closed_at, presence: true

  scope :recent, -> { order(business_date: :desc) }

  def difference
    counted_cash - expected_cash
  end

  def payway_verified?
    payway_batch_total.present?
  end

  def mercado_pago_verified?
    mercado_pago_total.present?
  end
end
