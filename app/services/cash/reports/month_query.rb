# frozen_string_literal: true

module Cash
  module Reports
    # How one month is going: what was sold and what went on fixed expenses.
    # Sales are read as totals, fixed expenses one by one. Figures are positive.
    # Dollars are reported apart, never added to pesos.
    class MonthQuery
      PESO_GROUPS = CashMovement::REPORTING_GROUPS.keys - %w[usd]

      Line = Struct.new(:key, :label, :amount, keyword_init: true)

      def initialize(month:)
        @month = month
      end

      def sold_by_group
        @sold_by_group ||= PESO_GROUPS.map do |group|
          Line.new(key: group, label: CashMovement::REPORTING_GROUP_LABELS.fetch(group), amount: sold[group])
        end
      end

      # A compensation sale reaches no arca: it is the one sale with no group.
      def sold_compensation = sold[nil]
      def sold_usd = sold["usd"]
      def sold_total = sold_by_group.sum(&:amount) + sold_compensation

      # The list and the two totals read the same rows, so they cannot disagree.
      def fixed_expenses
        @fixed_expenses ||= CashMovement.where(business_date: @month.all_month, category: "fixed_expense")
                                        .order(business_date: :desc, id: :desc)
                                        .to_a
      end

      def fixed_usd = -fixed_expenses.select { |row| row.account == "usd" }.sum(&:amount)
      def fixed_total = -fixed_expenses.reject { |row| row.account == "usd" }.sum(&:amount)

      private

      def sold
        @sold ||= CashMovement
                  .where(business_date: @month.all_month, category: "sale")
                  .group(:account)
                  .sum(:amount)
                  .each_with_object(Hash.new(0)) do |(account, amount), totals|
                    totals[account && CashMovement.reporting_group_for(account)] += amount
                  end
      end
    end
  end
end
