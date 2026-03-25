# frozen_string_literal: true

module SalesLedger
  module Reports
    class SalesByDateQuery
      def self.call(from:, to:)
        SalesLedger::Entry
          .where(sale_date: from..to)
          .group(:sale_date)
          .order(sale_date: :desc)
          .select(
            "sale_date",
            "SUM(total_amount) AS revenue",
            "SUM(quantity) AS units",
            "COUNT(DISTINCT ticket_number) AS tickets"
          )
      end
    end
  end
end
