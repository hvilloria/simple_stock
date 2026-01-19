# frozen_string_literal: true

class CreditNoteItem < ApplicationRecord
  belongs_to :credit_note
  belongs_to :product

  validates :quantity, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :unit_price, presence: true, numericality: { greater_than_or_equal_to: 0 }

  def total_price
    quantity * unit_price
  end
end
