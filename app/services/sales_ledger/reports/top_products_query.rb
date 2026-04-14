# frozen_string_literal: true

module SalesLedger
  module Reports
    class TopProductsQuery
      # Agrupa por oem_code y usa MIN(product_name_snapshot) como nombre representativo.
      # MVP: evita joins y funciona sin depender de la tabla products.
      # Mejora futura: hacer JOIN a products y usar products.name para nombre canónico.
      def self.call(from:, to:, limit: 20)
        SalesLedger::Entry
          .where(sale_date: from..to)
          .group(:oem_code)
          .order("SUM(quantity) DESC")
          .limit(limit)
          .select(
            "oem_code",
            "MIN(product_name_snapshot) AS product_name",
            "SUM(quantity) AS total_quantity",
            "SUM(total_amount) AS total_revenue"
          )
      end
    end
  end
end
