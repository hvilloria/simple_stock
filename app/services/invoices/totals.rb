module Invoices
  # Subtotal -> discount -> IVA -> total, in the order a supplier prints them.
  class Totals
    attr_reader :subtotal, :discount, :iva, :total

    def self.final_unit_cost(unit_price, discount_percentage:, iva_percentage:)
      price = decimal(unit_price)
      (price * (1 - rate(discount_percentage)) * (1 + rate(iva_percentage))).round(2)
    end

    def self.decimal(value) = BigDecimal((value || 0).to_s)
    def self.rate(percentage) = decimal(percentage) / 100

    def initialize(subtotal:, discount_percentage:, iva_percentage:)
      @subtotal = self.class.decimal(subtotal)
      @discount = (@subtotal * self.class.rate(discount_percentage)).round(2)
      @iva = ((@subtotal - @discount) * self.class.rate(iva_percentage)).round(2)
      @total = (@subtotal - @discount + @iva).round(2)
    end
  end
end
