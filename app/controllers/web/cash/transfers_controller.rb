# frozen_string_literal: true

module Web
  module Cash
    # Moving money between two arcas is the one gesture in the app that writes
    # two rows. The entry row already reads as the sentence it will write —
    # amount, from, to — so it writes the pair straight away, with no preview.
    class TransfersController < ApplicationController
      include CurrencyParser
      include SupplierOptions

      before_action :set_business_date

      def create
        authorize CashMovement, :create?
        return refuse_closed_day if day_closed?

        result = ::Cash::RecordTransfer.call(**transfer_params)
        return refuse(result.errors.join(", ")) if result.failure?

        @entry = ::Cash::DayQuery.entry_for(result.record)
        render_create
      end

      private

      # The fresh entry form comes back on Transferencia, with the error when
      # there is one.
      def render_create(status: :ok)
        @suppliers = supplier_options
        @day = ::Cash::DayQuery.new(@business_date)
        render :create, status: status
      end

      def refuse(message)
        @error = message
        render_create(status: :unprocessable_entity)
      end

      def transfer_params
        {
          from:          params[:from],
          to:            params[:to],
          amount:        submitted_amount,
          business_date: @business_date,
          user:          current_user,
          description:   params[:description].presence
        }
      end

      # Argentine-formatted input converts to a plain decimal string; garbage is
      # passed through unchanged so Cash::RecordTransfer refuses it with its own
      # message instead of reading it as blank.
      def submitted_amount
        raw = params[:amount]
        decimal_string_from(raw) || raw
      end

      def set_business_date
        @business_date = Date.parse(params[:business_date])
      end

      def day_closed?
        DailyClosing.exists?(business_date: @business_date)
      end

      # A closed day offers no form at all, so a submission means the day closed
      # in another tab while this screen was open: there is nothing left on
      # screen to hang the message on, and the screen reloads.
      def refuse_closed_day
        flash[:alert] = "El día está cerrado."
        redirect_to web_cash_day_path(@business_date)
      end
    end
  end
end
