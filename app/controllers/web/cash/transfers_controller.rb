# frozen_string_literal: true

module Web
  module Cash
    # Moving money between two arcas is the one gesture in the app that writes
    # two rows, so it does not go through either live row: it asks for an origin
    # and a destination, shows the pair it is about to write, and only then
    # writes it.
    class TransfersController < ApplicationController
      include CurrencyParser

      before_action :set_business_date

      def preview
        authorize CashMovement, :create?
        return refuse_closed_day if day_closed?

        render_result(dry_run)
      end

      def create
        authorize CashMovement, :create?
        return refuse_closed_day if day_closed?

        result = ::Cash::RecordTransfer.call(**transfer_params)
        return render_result(result) if result.failure?

        @legs = result.record
        @day = ::Cash::DayQuery.new(@business_date)
        render :create
      end

      private

      # The preview is the real write, rolled back. Same service, same
      # validations, same rows, so what the cashier is shown cannot drift from
      # what confirming writes: the only thing the two calls differ in is
      # whether the transaction survives.
      def dry_run
        result = nil
        ActiveRecord::Base.transaction do
          result = ::Cash::RecordTransfer.call(**transfer_params)
          raise ActiveRecord::Rollback
        end
        result
      end

      def render_result(result)
        @legs   = result.record
        @error  = result.errors.join(", ") if result.failure?
        @fields = params.slice(:business_date, :from, :to, :amount, :description).permit!.to_h.symbolize_keys
        render :preview, status: result.failure? ? :unprocessable_entity : :ok
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
