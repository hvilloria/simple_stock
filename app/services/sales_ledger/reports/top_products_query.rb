# frozen_string_literal: true

module SalesLedger
  module Reports
    class TopProductsQuery
      # Agrupa por oem_code y devuelve los 15 OEM con mayor FRECUENCIA:
      # frecuencia = cantidad de tickets distintos en que apareció el OEM.
      # Columnas disponibles: oem_code, product_name, product_source, frequency, total_quantity, total_revenue.
      def self.call(from:, to:, limit: 15, product_source: nil)
        scope = SalesLedger::Entry.where(sale_date: from..to)
        scope = scope.where(product_source: product_source) if product_source.present?

        scope
          .group(:oem_code)
          .order(Arel.sql("COUNT(DISTINCT ticket_number) DESC"))
          .limit(limit)
          .select(
            "oem_code",
            "MIN(product_name_snapshot) AS product_name",
            "MIN(product_source) AS product_source",
            "COUNT(DISTINCT ticket_number) AS frequency",
            "SUM(quantity) AS total_quantity",
            "SUM(total_amount) AS total_revenue"
          )
      end
    end
  end
end
