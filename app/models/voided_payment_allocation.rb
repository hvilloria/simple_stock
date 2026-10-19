# frozen_string_literal: true

# What a voided payment had covered: a copy of each allocation it lost.
class VoidedPaymentAllocation < ApplicationRecord
  belongs_to :payment
  belongs_to :order

  def voided? = true
end
