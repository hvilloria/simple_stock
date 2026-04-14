# frozen_string_literal: true

module SalesLedger
  module Reports
    class SalesByDateQuery
      def self.call(from:, to:)
        subquery = SalesLedger::Entry
          .where(sale_date: from..to)
          .select(
            "sale_date",
            "ticket_number",
            "ticket_total_amount",
            "payment_method",
            "total_amount",
            "quantity",
            "ROW_NUMBER() OVER (PARTITION BY sale_date, ticket_number ORDER BY id) AS rn"
          )

        SalesLedger::Entry
          .from("(#{subquery.to_sql}) AS entries")
          .group("sale_date", "payment_method")
          .order("sale_date DESC", "payment_method")
          .select(
            "sale_date",
            "payment_method",
            "SUM(total_amount) AS revenue",
            "SUM(CASE WHEN rn = 1 THEN ticket_total_amount ELSE 0 END) AS ticket_total_amount",
            "SUM(quantity) AS units",
            "COUNT(DISTINCT ticket_number) AS tickets"
          )
      end
    end
  end
end
