# frozen_string_literal: true

module Web
  module Cash
    class MovementsController < ApplicationController
      include CurrencyParser

      OUTFLOW_CATEGORIES = %w[suppliers fixed_expense].freeze

      def create
        authorize CashMovement, :create?

        @business_date = Date.parse(params[:business_date])
        return refuse("El día está cerrado.") if day_closed?
        return refuse("Esa categoría no se carga en la caja del día.") unless drawer_category?

        amount = signed_amount
        return refuse("El monto no es un número.") if amount.nil?

        result = ::Cash::RecordMovement.call(
          business_date: @business_date,
          account: account_for(params[:category], params[:channel]),
          amount: amount,
          category: params[:category],
          subcategory: params[:subcategory].presence,
          channel: params[:channel].presence,
          description: params[:description].presence,
          user: current_user
        )

        return refuse(result.errors.join(", ")) if result.failure?

        @movement = result.record
        @day = ::Cash::DayQuery.new(@business_date)
        render :create
      end

      private

      def drawer_category?
        CashMovementPolicy::DRAWER_CATEGORIES.include?(params[:category])
      end

      def day_closed?
        DailyClosing.exists?(business_date: @business_date)
      end

      # A sale lands in the arca its channel implies; an expense loaded here came
      # out of the till by definition. An unknown channel yields a nil account,
      # which the model rejects.
      def account_for(category, channel)
        return "drawer" unless category == "sale"

        CashMovement::CHANNEL_ACCOUNTS[channel.to_s]
      end

      # The cashier types a bare amount; the category decides the sign.
      def signed_amount
        decimal = decimal_string_from(params[:amount])
        return nil if decimal.nil?

        OUTFLOW_CATEGORIES.include?(params[:category]) ? "-#{decimal.delete_prefix('-')}" : decimal
      end

      def refuse(message)
        @error = message
        @day = ::Cash::DayQuery.new(@business_date)
        render :create, status: :unprocessable_entity
      end
    end
  end
end
