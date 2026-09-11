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

      # The arca filter offers the four reporting groups, never the six arcas:
      # the history reads at the grain the report reads at, so a filtered
      # history still adds up to the figures it explains.
      GROUP_OPTIONS = CashMovement::REPORTING_GROUP_LABELS.map { |group, label| [ label, group ] }.freeze

      # A compensation has no arca, so the arca filter cannot reach it and its
      # category is the same "Venta" every sale carries; the channel is the
      # only handle the period's compensations have.
      CHANNEL_OPTIONS = CashMovement::CHANNEL_LABELS.map { |channel, label| [ label, channel ] }.freeze

      CATEGORY_OPTIONS = CashMovement::CATEGORY_LABELS.map { |category, label| [ label, category ] }.freeze

      def balance
        authorize CashMovement, :balance_report?

        load_range
        @rows = ::Cash::Reports::BalanceQuery.call(from: @from, to: @to)
        @breakdown = ::Cash::Reports::FixedExpenseBreakdownQuery.new(from: @from, to: @to)
      end

      def history
        authorize CashMovement, :movement_history?

        load_range
        @group = params[:group].to_s
        @channel = params[:channel].to_s
        @category = params[:category].to_s
        @search = params[:search].to_s.strip
        @group_options = GROUP_OPTIONS
        @channel_options = CHANNEL_OPTIONS
        @category_options = CATEGORY_OPTIONS
        @pagy, @movements = pagy(
          ::Cash::Reports::MovementsQuery.call(
            from: @from, to: @to, group: @group, channel: @channel,
            category: @category, search: @search
          )
        )
      end

      private

      def load_range
        @period = PERIODS.include?(params[:period]) ? params[:period] : DEFAULT_PERIOD
        @period_options = PERIOD_OPTIONS
        @from, @to = resolve_range
      end

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
