# frozen_string_literal: true

module Cash
  module Reports
    # How much money there is, and where, at the end of one day: each reporting
    # group is the SUM of every movement of its arcas up to and including that
    # date. No total: USD stands alone.
    class HoldingsQuery
      LABELS = CashMovement::REPORTING_GROUP_LABELS.merge("usd" => "Dólares").freeze

      Row = Struct.new(:group, :label, :amount, keyword_init: true) do
        def usd? = group == "usd"
      end

      def initialize(on:)
        @on = on
      end

      def holdings
        @holdings ||= CashMovement::REPORTING_GROUPS.keys.map do |group|
          Row.new(group: group, label: LABELS.fetch(group), amount: totals[group])
        end
      end

      private

      # A compensation sale has no account, so it reaches no arca and is left
      # out by the account filter.
      def totals
        @totals ||= CashMovement
                    .where(business_date: ..@on, account: CashMovement::ACCOUNT_REPORTING_GROUPS.keys)
                    .group(:account)
                    .sum(:amount)
                    .each_with_object(Hash.new(0)) do |(account, amount), sums|
                      sums[CashMovement.reporting_group_for(account)] += amount
                    end
      end
    end
  end
end
