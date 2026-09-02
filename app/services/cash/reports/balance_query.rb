# frozen_string_literal: true

module Cash
  module Reports
    # The replacement for the Caja Grande sheet: one row per reporting group,
    # every figure a SUM over rows. Nothing here is a stored total.
    class BalanceQuery
      # Columns are named after the categories, never income/expense: a deposit
      # is money changing place, not an expense.
      CATEGORY_COLUMNS = {
        "sale"              => :sales,
        "suppliers"         => :suppliers,
        "fixed_expense"     => :fixed_expenses,
        "partner"           => :partner,
        "internal_transfer" => :transfers,
        "cash_discrepancy"  => :discrepancies
      }.freeze

      Row = Struct.new(:group, :label, :opening, :sales, :suppliers, :fixed_expenses,
                       :partner, :transfers, :discrepancies, :closing,
                       keyword_init: true)

      def self.call(from:, to:) = new(from: from, to: to).call

      def initialize(from:, to:)
        @from = from
        @to = to
      end

      def call = rows

      def rows
        @rows ||= CashMovement::REPORTING_GROUPS.keys.map { |group| build_row(group) }
      end

      private

      def build_row(group)
        in_range = in_range_totals[group]
        columns = CATEGORY_COLUMNS.to_h { |category, column| [ column, in_range[category] ] }
        # An opening_balance row inside the range is the starting position, not
        # money that came in, so it lands in the opening figure. Every category
        # is either a column or that one, which is why the row reconciles.
        opening = before_range_totals[group] + in_range["opening_balance"]
        # Read from the rows, not from `opening` plus the columns: derived from
        # the figures it is meant to check, the invariant could not fail.
        closing = before_range_totals[group] + in_range.values.sum

        Row.new(
          group: group,
          label: CashMovement::REPORTING_GROUP_LABELS.fetch(group),
          opening: opening,
          closing: closing,
          **columns
        )
      end

      # One round trip for the history before the range.
      def before_range_totals
        @before_range_totals ||= begin
          sums = CashMovement.where(business_date: ...@from).group(:account).sum(:amount)

          sums.each_with_object(Hash.new(0)) do |(account, amount), totals|
            totals[group_of(account)] += amount if account
          end
        end
      end

      # One round trip for the range itself, split by category in SQL.
      def in_range_totals
        @in_range_totals ||= begin
          sums = CashMovement.between(@from, @to).group(:account, :category).sum(:amount)
          totals = Hash.new { |cache, group| cache[group] = Hash.new(0) }

          sums.each do |(account, category), amount|
            totals[group_of(account)][category] += amount if account
          end
          totals
        end
      end

      # A row with no account is a compensation sale: it reaches no arca and so
      # belongs to no group.
      def group_of(account) = CashMovement.reporting_group_for(account)
    end
  end
end
