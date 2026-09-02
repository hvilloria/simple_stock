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
        return refuse("El monto no puede ser cero.") if zero_amount?(amount)

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

      def edit
        load_movement
        authorize @movement, :update?
        return refuse_closed_day if day_closed?

        render :edit
      end

      def update
        load_movement
        authorize @movement
        return refuse_closed_day if day_closed?
        return refuse_edit("Esa categoría no se carga en la caja del día.") unless drawer_category?

        amount = signed_amount
        return refuse_edit("El monto no es un número.") if amount.nil?
        return refuse_edit("El monto no puede ser cero.") if zero_amount?(amount)

        saved = @movement.update(
          amount: amount,
          category: params[:category],
          subcategory: params[:subcategory].presence,
          channel: params[:channel].presence,
          account: account_for(params[:category], params[:channel]),
          description: params[:description].presence
        )

        return refuse_edit(@movement.errors.full_messages.join(", ")) unless saved

        @day = ::Cash::DayQuery.new(@business_date)
        render :update
      end

      def destroy
        load_movement
        authorize @movement
        return refuse_closed_day if day_closed?

        @movement.destroy
        @day = ::Cash::DayQuery.new(@business_date)
        render :destroy
      end

      private

      def load_movement
        @movement = CashMovement.find(params[:id])
        @business_date = @movement.business_date
      end

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

      def zero_amount?(decimal_string)
        BigDecimal(decimal_string).zero?
      end

      # The cashier types a bare amount; the category decides the sign.
      def signed_amount
        decimal = decimal_string_from(params[:amount])
        return nil if decimal.nil?

        OUTFLOW_CATEGORIES.include?(params[:category]) ? "-#{decimal.delete_prefix('-')}" : decimal
      end

      # A rejected correction keeps the form row on screen, with the reason, the
      # way a rejected load keeps the live row.
      def refuse_edit(message)
        @error = message
        @movement.restore_attributes
        render :edit, status: :unprocessable_entity
      end

      # The day can close in another tab while this screen is open. There is no
      # live row to hang the message on once it is closed, so the screen reloads.
      def refuse_closed_day
        flash[:alert] = "El día está cerrado."
        redirect_to web_cash_day_path(@business_date)
      end

      def refuse(message)
        @error = message
        @day = ::Cash::DayQuery.new(@business_date)
        render :create, status: :unprocessable_entity
      end
    end
  end
end
