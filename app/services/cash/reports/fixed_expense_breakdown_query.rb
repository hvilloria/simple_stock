# frozen_string_literal: true

module Cash
  module Reports
    # Expands the fixed-expenses column of the balance report into the six
    # subcategories against the arcas they were paid from. It reads at the
    # reporting group, the grain the report's rows use: a breakdown that
    # disagreed with the row it expands would be worse than no breakdown.
    #
    # A query of its own, and not another GROUP BY inside BalanceQuery, so that
    # the two figures are aggregated independently and can genuinely disagree.
    class FixedExpenseBreakdownQuery
      Row = Struct.new(:subcategory, :label, :amounts, keyword_init: true) do
        def amount_for(group) = amounts.fetch(group)
      end

      def self.call(from:, to:) = new(from: from, to: to).call

      def initialize(from:, to:)
        @from = from
        @to = to
      end

      def call = rows

      def rows
        @rows ||= CashMovement::SUBCATEGORY_LABELS.map do |subcategory, label|
          Row.new(subcategory: subcategory, label: label, amounts: amounts_for(subcategory))
        end
      end

      # Summed from the breakdown itself rather than read back from the report:
      # a total copied from the column it is checked against could not disagree
      # with it. No figure across groups, for the same reason the report has no
      # grand total: USD stands alone.
      def totals_by_group
        @totals_by_group ||= groups.to_h { |group| [ group, rows.sum { |row| row.amount_for(group) } ] }
      end

      def groups = CashMovement::REPORTING_GROUPS.keys
      def group_label(group) = CashMovement::REPORTING_GROUP_LABELS.fetch(group)

      private

      def amounts_for(subcategory)
        groups.to_h { |group| [ group, totals[subcategory][group] ] }
      end

      # One round trip: every subcategory and every arca in a single GROUP BY.
      def totals
        @totals ||= begin
          sums = CashMovement.between(@from, @to)
                             .where(category: "fixed_expense")
                             .group(:subcategory, :account)
                             .sum(:amount)
          grouped = Hash.new { |cache, subcategory| cache[subcategory] = Hash.new(0) }

          sums.each do |(subcategory, account), amount|
            grouped[subcategory][CashMovement.reporting_group_for(account)] += amount
          end
          grouped
        end
      end
    end
  end
end
