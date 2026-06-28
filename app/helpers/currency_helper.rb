module CurrencyHelper
  # Formatea un número con formato argentino: 1.500.000,50
  # precision: cantidad de decimales (default: 2)
  # Retorna string vacío si value es nil (útil para campos opcionales)
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

  # Formatea moneda con símbolo: ARS 1.500.000,50
  # unit: símbolo de moneda (default: "ARS ")
  # precision: cantidad de decimales (default: 2)
  def currency_ar(value, unit: "ARS ", precision: 2)
    return "" if value.nil?
    formatted = number_ar(value, precision: precision)
    "#{unit}#{formatted}"
  end

  # Formatea moneda sin decimales: ARS 1.500.000
  def currency_ar_int(value, unit: "ARS ")
    currency_ar(value, unit: unit, precision: 0)
  end

  # Formatea cantidad (sin decimales): 1.500
  def quantity_ar(value)
    number_ar(value, precision: 0)
  end

  # Formatea un teléfono de contacto para mostrar, a partir de los dígitos.
  # 10 dígitos -> "11 5555-1234"; 8 dígitos -> "5555-1234".
  # Otros largos: devuelve los dígitos, o el valor original como fallback.
  def format_contact_phone(raw)
    digits = raw.to_s.gsub(/\D/, "")
    case digits.length
    when 10 then "#{digits[0, 2]} #{digits[2, 4]}-#{digits[6, 4]}"
    when 8  then "#{digits[0, 4]}-#{digits[4, 4]}"
    else digits.presence || raw.to_s
    end
  end
end
