# frozen_string_literal: true

# Single money parser for every controller that reads an amount from a form.
#
# Returns nil for anything it cannot parse, so callers reject the request instead
# of silently booking 0. Never returns 0.0 as a stand-in for "invalid", and never
# "repairs" malformed input into a number: a wrong number is worse than nil.
#
#   "1.500.000,50" -> 1500000.50  (Argentine: dots = thousands, comma = decimal)
#   "1.500.000"    -> 1500000     (Argentine thousands, no decimals)
#   "1500,50"      -> 1500.50     (comma decimal, no thousands separator)
#   "1500.50"      -> 1500.50     (clean decimal, as sent by currency-input JS)
#   "1.200"        -> 1.2         (a single dot is a decimal point, not a separator)
#   "-500"         -> -500        (callers/services reject non-positive amounts)
#   "1..5" / "12.34.56" / "1.5000,00" / "abc" / "" -> nil
#
# Usage:
#   include CurrencyParser
#   amount = parse_amount(params[:amount])
#
module CurrencyParser
  extend ActiveSupport::Concern

  # Comma is the decimal separator. The integer part is either well-formed
  # Argentine thousands groups (1-3 digits, then groups of exactly 3) or plain digits.
  COMMA_DECIMAL = /\A-?(\d{1,3}(\.\d{3})+|\d+),\d+\z/

  # Dots as thousands separators require at least two groups; with a single dot the
  # value is read as a decimal instead (see PLAIN_DECIMAL).
  DOT_THOUSANDS = /\A-?\d{1,3}(\.\d{3}){2,}\z/

  PLAIN_DECIMAL = /\A-?\d+(\.\d+)?\z/

  private

  # @param raw [String, Numeric, nil] amount as typed/submitted
  # @return [BigDecimal, nil] nil when blank or not a valid number
  def parse_amount(raw)
    return raw.to_d if raw.is_a?(Numeric)
    return nil if raw.blank?

    value = raw.to_s.strip

    normalized =
      case value
      when COMMA_DECIMAL then value.delete(".").tr(",", ".")
      when DOT_THOUSANDS then value.delete(".")
      when PLAIN_DECIMAL then value
      end

    return nil if normalized.nil?

    BigDecimal(normalized)
  end
end
