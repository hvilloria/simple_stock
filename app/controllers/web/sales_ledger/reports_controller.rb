# frozen_string_literal: true

module Web
  module SalesLedger
    class ReportsController < ApplicationController
      def index
        from_raw = parse_date(params[:from]) || Date.current.beginning_of_month
        to_raw   = parse_date(params[:to])   || Date.current
        # Si from > to, intercambiar para evitar rango vacío silencioso
        @from, @to = [ from_raw, to_raw ].minmax

        @summary        = ::SalesLedger::Reports::SummaryQuery.call(from: @from, to: @to)
        @sales_by_date  = ::SalesLedger::Reports::SalesByDateQuery.call(from: @from, to: @to)
        @top_products   = ::SalesLedger::Reports::TopProductsQuery.call(from: @from, to: @to)
        @recent_entries = ::SalesLedger::Reports::RecentEntriesQuery.call(from: @from, to: @to)
      end

      private

      def parse_date(str)
        Date.parse(str) if str.present?
      rescue Date::Error
        nil
      end
    end
  end
end
