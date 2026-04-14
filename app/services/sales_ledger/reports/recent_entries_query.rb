# frozen_string_literal: true

module SalesLedger
  module Reports
    class RecentEntriesQuery
      def self.call(from:, to:, limit: 50)
        SalesLedger::Entry
          .where(sale_date: from..to)
          .order(sale_date: :desc, created_at: :desc)
          .limit(limit)
      end
    end
  end
end
