# frozen_string_literal: true

module Web
  module Cash
    class ReportsController < ApplicationController
      PERIODS = %w[week fortnight month custom].freeze
      DEFAULT_PERIOD = "month"

      # The owner picks his own cadence, so the presets are offered and none is
      # imposed beyond the month the screen opens on.
      PERIOD_OPTIONS = [
        [ "Semana", "week" ],
        [ "Quincena", "fortnight" ],
        [ "Mes", "month" ],
        [ "Personalizado", "custom" ]
      ].freeze

      def balance
        authorize CashMovement, :balance_report?

        @period = PERIODS.include?(params[:period]) ? params[:period] : DEFAULT_PERIOD
        @period_options = PERIOD_OPTIONS
        @from, @to = resolve_range
        @rows = ::Cash::Reports::BalanceQuery.call(from: @from, to: @to)
        @breakdown = ::Cash::Reports::FixedExpenseBreakdownQuery.new(from: @from, to: @to)
      end

      private

      def resolve_range
        case @period
        when "week"      then week_range
        when "fortnight" then fortnight_range
        when "custom"    then custom_range || month_range
        else month_range
        end
      end

      def week_range
        [ Date.current.beginning_of_week(:monday), Date.current.end_of_week(:monday) ]
      end

      # The quincena as the shop counts it: the first half of the month, or the
      # sixteenth to its end.
      def fortnight_range
        today = Date.current
        return [ today.beginning_of_month, today.beginning_of_month + 14 ] if today.day <= 15

        [ today.beginning_of_month + 15, today.end_of_month ]
      end

      def month_range
        [ Date.current.beginning_of_month, Date.current.end_of_month ]
      end

      # A range typed by hand is only a range once both ends parse and they are
      # in order; anything else falls back to the month.
      def custom_range
        from = parse_date(params[:from])
        to   = parse_date(params[:to])
        return nil if from.nil? || to.nil? || from > to

        [ from, to ]
      end

      def parse_date(value)
        Date.parse(value)
      rescue Date::Error, TypeError
        nil
      end
    end
  end
end
