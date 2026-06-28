# frozen_string_literal: true

module Payments
  # Shared cash-rounding rule for discounted cash collections.
  #
  # When a discount is granted AND the amount is paid in cash, the cash to
  # collect is rounded UP to the next hundred. Uses BigDecimal to avoid float
  # drift. Always returns an Integer.
  #
  #   round_up_to_hundred(639_697.5) => 639_700
  #   round_up_to_hundred(950)       => 1_000
  #   round_up_to_hundred(900)       => 900
  module CashRounding
    module_function

    def round_up_to_hundred(amount)
      (amount.to_d / 100).ceil * 100
    end
  end
end
