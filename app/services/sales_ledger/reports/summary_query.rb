# frozen_string_literal: true

module SalesLedger
  module Reports
    class SummaryQuery
      def self.call(from:, to:, product_source: nil)
        scope = SalesLedger::Entry.where(sale_date: from..to)
        scope = scope.where(product_source: product_source) if product_source.present?

        reported_subquery = scope
          .select("DISTINCT ON (ticket_number) ticket_number, ticket_total_amount")
          .order("ticket_number, id")

        reported = SalesLedger::Entry
          .from("(#{reported_subquery.to_sql}) AS entries")
          .sum("ticket_total_amount")

        {
          revenue:         scope.sum(:total_amount),
          reported:        reported,
          units:           scope.sum(:quantity),
          tickets:         scope.distinct.count(:ticket_number),
          unique_products: scope.distinct.count(:oem_code)
        }
      end
    end
  end
end
