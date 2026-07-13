# frozen_string_literal: true

# Concern to parse monetary values from Argentine format to the database format
#
# Converts: "1.500.000,50" → 1500000.50
#
# Usage in controllers:
#   include CurrencyParser
#
#   amount = parse_amount(params[:amount])
#   exchange_rate = parse_amount(params[:exchange_rate])
#
module CurrencyParser
  extend ActiveSupport::Concern

  private

  # Converts Argentine format to decimal for the database
  # @param amount_string [String] Value in Argentine format (e.g.: "1.500,00") or already clean (e.g.: "1500.00")
  # @return [Float, nil] Decimal value or nil if the string is empty
  #
  # Automatically detects the format:
  # - If it has a comma → Argentine format: "1.500,00" → 1500.00
  # - If it only has a dot → already clean: "1500.00" → 1500.00
  # - If it has a dot and a comma → Argentine format: "1.500.000,50" → 1500000.50
  def parse_amount(amount_string)
    return nil if amount_string.blank?

    value = amount_string.to_s.strip

    # If it contains a comma, it is Argentine format → clean it
    if value.include?(",")
      # Remove dots (thousands) and change comma to dot (decimal)
      # "1.500.000,50" → "1500000.50"
      cleaned = value.gsub(/\./, "").gsub(/,/, ".")
      cleaned.to_f
    else
      # Already in clean format with a decimal dot (or it is an integer)
      # "1500.00" → 1500.00
      # "1500" → 1500.0
      value.to_f
    end
  end
end
