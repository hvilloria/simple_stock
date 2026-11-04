# frozen_string_literal: true

module Cash
  # One summary row per cash day, for the "Resumen de días" table.
  class DaysSummaryQuery
    Row = Struct.new(:date, :units_sold, :sales_by_group, :counted_cash, keyword_init: true) do
      def closed? = !counted_cash.nil?
      def today? = date == Date.current
    end

    def self.dates(today: Date.current)
      (CashMovement.distinct.pluck(:business_date) |
        DailyClosing.pluck(:business_date) |
        [ today ]).sort.reverse
    end

    def initialize(dates)
      @dates = dates
    end

    def rows
      sales = sales_by_date
      units = units_by_date
      closings = DailyClosing.where(business_date: @dates).pluck(:business_date, :counted_cash).to_h

      @dates.map do |date|
        Row.new(date: date, units_sold: units.fetch(date, 0),
                sales_by_group: DayQuery.fold_by_group(sales.fetch(date, {})),
                counted_cash: closings[date])
      end
    end

    private

    def sales_by_date
      CashMovement.where(business_date: @dates).sales.group(:business_date, :channel).sum(:amount)
                  .each_with_object(Hash.new { |hash, date| hash[date] = {} }) do |((date, channel), amount), by_date|
        by_date[date][channel] = amount
      end
    end

    # A note counts on the day it became fully paid, so installments never repeat it.
    def units_by_date
      Order.where(settled_on: @dates).where.not(status: "cancelled")
           .joins(:order_items).group(:settled_on).sum("order_items.quantity")
    end
  end
end
