# frozen_string_literal: true

module SalesLedger
  module Reports
    class SummaryQuery
      def self.call(from:, to:)
        scope = SalesLedger::Entry.where(sale_date: from..to)
        {
          revenue:         scope.sum(:total_amount),
          units:           scope.sum(:quantity),
          tickets:         scope.distinct.count(:ticket_number),
          unique_products: scope.distinct.count(:oem_code)
        }
      end
    end
  end
end
