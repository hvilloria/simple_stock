# frozen_string_literal: true

module Web
  module SalesLedger
    class ReportsController < ApplicationController
      def index
        from_raw = parse_date(params[:from]) || Date.current.beginning_of_month
        to_raw   = parse_date(params[:to])   || Date.current
        # Si from > to, intercambiar para evitar rango vacío silencioso
        @from, @to = [ from_raw, to_raw ].minmax

        @product_source = params[:product_source].presence
        @product_source = nil unless ::SalesLedger::Entry::PRODUCT_SOURCES.include?(@product_source)

        query_opts = { from: @from, to: @to, product_source: @product_source }

        @summary       = ::SalesLedger::Reports::SummaryQuery.call(**query_opts)
        @sales_by_date = ::SalesLedger::Reports::SalesByDateQuery.call(**query_opts)
        @top_products  = ::SalesLedger::Reports::TopProductsQuery.call(**query_opts)
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
