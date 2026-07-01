# frozen_string_literal: true

module Payments
  # Shared rounding rule for discounted cash collections.
  #
  # When a discount is granted AND the amount is paid in cash, the cash to
  # collect is rounded to the NEAREST multiple of 100, with a remainder of
  # exactly 50 rounding DOWN (remainder 1–50 → down, 51–99 → up). Uses
  # BigDecimal to avoid float drift. Always returns an Integer.
  #
  #   round_to_nearest_hundred(22_050)  => 22_000
  #   round_to_nearest_hundred(22_051)  => 22_100
  #   round_to_nearest_hundred(639_697.5) => 639_700
  #   round_to_nearest_hundred(900)      => 900
  module CashRounding
    module_function

    def round_to_nearest_hundred(amount)
      ((amount.to_d / 100).round(0, :half_down) * 100).to_i
    end
  end
end
