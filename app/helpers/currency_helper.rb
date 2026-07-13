module CurrencyHelper
  # Formats a number in Argentine format: 1.500.000,50
  # precision: number of decimals (default: 2)
  # Returns an empty string if value is nil (useful for optional fields)
  def number_ar(value, precision: 2)
    return "" if value.nil?
    return (precision == 0 ? "0" : "0,#{'0' * precision}") if value == 0

    number_with_precision(
      value,
      precision: precision,
      delimiter: ".",
      separator: ","
    )
  end

  # Formats currency with a symbol: ARS 1.500.000,50
  # unit: currency symbol (default: "ARS ")
  # precision: number of decimals (default: 2)
  def currency_ar(value, unit: "ARS ", precision: 2)
    return "" if value.nil?
    formatted = number_ar(value, precision: precision)
    "#{unit}#{formatted}"
  end

  # Formats currency without decimals: ARS 1.500.000
  def currency_ar_int(value, unit: "ARS ")
    currency_ar(value, unit: unit, precision: 0)
  end

  # Formats a quantity (without decimals): 1.500
  def quantity_ar(value)
    number_ar(value, precision: 0)
  end

  # Formats a contact phone for display, starting from the digits.
  # 10 digits -> "11 5555-1234"; 8 digits -> "5555-1234".
  # Other lengths: returns the digits, or the original value as a fallback.
  def format_contact_phone(raw)
    digits = raw.to_s.gsub(/\D/, "")
    case digits.length
    when 10 then "#{digits[0, 2]} #{digits[2, 4]}-#{digits[6, 4]}"
    when 8  then "#{digits[0, 4]}-#{digits[4, 4]}"
    else digits.presence || raw.to_s
    end
  end
end
