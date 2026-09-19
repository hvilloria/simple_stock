# frozen_string_literal: true

module Cash
  module Reports
    # How one month is going: what was sold and what went on fixed expenses.
    # Figures are positive. Dollars are reported apart, never added to pesos.
    class MonthQuery
      PESO_GROUPS = CashMovement::REPORTING_GROUPS.keys - %w[usd]

      Line = Struct.new(:key, :label, :amount, keyword_init: true)
      Sum = Struct.new(:category, :group, :subcategory, :amount)

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

      def fixed_by_subcategory
        @fixed_by_subcategory ||= fixed_pesos
                                  .reject { |_, amount| amount.zero? }
                                  .sort_by { |_, amount| -amount }
                                  .map do |subcategory, amount|
                                    Line.new(key: subcategory, label: CashMovement.subcategory_label(subcategory),
                                             amount: amount)
                                  end
      end

      def fixed_usd = -sums.select { |sum| fixed?(sum) && sum.group == "usd" }.sum(&:amount)
      def fixed_total = fixed_by_subcategory.sum(&:amount)

      private

      def sold
        @sold ||= totals_by(:group) { |sum| sum.category == "sale" }
      end

      def fixed_pesos
        totals_by(:subcategory) { |sum| fixed?(sum) && sum.group != "usd" }.transform_values(&:-@)
      end

      def fixed?(sum) = sum.category == "fixed_expense"

      def totals_by(attribute, &filter)
        sums.select(&filter).each_with_object(Hash.new(0)) { |sum, totals| totals[sum[attribute]] += sum.amount }
      end

      def sums
        @sums ||= CashMovement
                  .where(business_date: @month.all_month, category: %w[sale fixed_expense])
                  .group(:category, :account, :subcategory)
                  .sum(:amount)
                  .map do |(category, account, subcategory), amount|
                    Sum.new(category, account && CashMovement.reporting_group_for(account), subcategory, amount)
                  end
      end
    end
  end
end
