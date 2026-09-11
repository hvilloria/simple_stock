# frozen_string_literal: true

module Web
  module Cash
    class ClosingsController < ApplicationController
      include CurrencyParser
      include SupplierOptions

      before_action :set_business_date

      def new
        authorize DailyClosing.new, :new?

        @day = ::Cash::DayQuery.new(@business_date)
        # The screen shows the still-open day behind the modal, live row and all.
        @suppliers = supplier_options
      end

      def create
        authorize DailyClosing.new, :create?

        result = ::Cash::CloseDay.call(
          business_date: @business_date,
          counted_cash: counted_amount,
          payway_batch_total: optional_amount(params[:payway_batch_total]),
          mercado_pago_total: optional_amount(params[:mercado_pago_total]),
          note: params[:note].presence,
          user: current_user
        )

        return refuse(result.errors.join(", ")) if result.failure?

        redirect_to web_cash_day_path(@business_date), notice: "Día cerrado."
      end

      private

      def set_business_date
        @business_date = Date.parse(params[:day_business_date])
      end

      # Argentine-formatted input converts to a plain decimal string; garbage
      # input is passed through unchanged so Cash::CloseDay's own validation
      # rejects it with the right message instead of reading it as blank.
      def counted_amount
        raw = params[:counted_cash]
        decimal_string_from(raw) || raw
      end

      def optional_amount(raw)
        return nil if raw.blank?

        decimal_string_from(raw) || raw
      end

      def refuse(message)
        @error = message
        @day = ::Cash::DayQuery.new(@business_date)
        @suppliers = supplier_options
        render :new, status: :unprocessable_entity
      end
    end
  end
end
