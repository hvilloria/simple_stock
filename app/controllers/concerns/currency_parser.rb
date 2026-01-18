# frozen_string_literal: true

# Concern para parsear valores monetarios del formato argentino al formato de base de datos
#
# Convierte: "1.500.000,50" → 1500000.50
#
# Uso en controllers:
#   include CurrencyParser
#
#   amount = parse_amount(params[:amount])
#   exchange_rate = parse_amount(params[:exchange_rate])
#
module CurrencyParser
  extend ActiveSupport::Concern

  private

  # Convierte formato argentino a decimal para la base de datos
  # @param amount_string [String] Valor en formato argentino (ej: "1.500,00") o ya limpio (ej: "1500.00")
  # @return [Float, nil] Valor decimal o nil si el string está vacío
  #
  # Detecta automáticamente el formato:
  # - Si tiene coma → formato argentino: "1.500,00" → 1500.00
  # - Si solo tiene punto → ya está limpio: "1500.00" → 1500.00
  # - Si tiene punto y coma → formato argentino: "1.500.000,50" → 1500000.50
  def parse_amount(amount_string)
    return nil if amount_string.blank?

    value = amount_string.to_s.strip

    # Si contiene coma, es formato argentino → limpiar
    if value.include?(",")
      # Remover puntos (miles) y cambiar coma por punto (decimal)
      # "1.500.000,50" → "1500000.50"
      cleaned = value.gsub(/\./, "").gsub(/,/, ".")
      cleaned.to_f
    else
      # Ya está en formato limpio con punto decimal (o es entero)
      # "1500.00" → 1500.00
      # "1500" → 1500.0
      value.to_f
    end
  end
end
