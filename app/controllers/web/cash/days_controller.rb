# frozen_string_literal: true

module Web
  module Cash
    class DaysController < ApplicationController
      def index
        authorize CashMovement, :index?

        redirect_to web_cash_day_path(Date.current)
      end

      def show
        authorize CashMovement, :index?

        business_date = parse_business_date
        return redirect_to web_cash_day_path(Date.current) if business_date.nil?

        @business_date = business_date
        @day = ::Cash::DayQuery.new(@business_date)
      end

      private

      def parse_business_date
        Date.parse(params[:business_date])
      rescue Date::Error, TypeError
        nil
      end
    end
  end
end
