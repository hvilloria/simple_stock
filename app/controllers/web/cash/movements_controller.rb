# frozen_string_literal: true

module Web
  module Cash
    class MovementsController < ApplicationController
      include CurrencyParser
      include SupplierOptions

      OUTFLOW_CATEGORIES = %w[suppliers fixed_expense].freeze

      def create
        authorize CashMovement, :create?
        deny_forbidden_category!

        @business_date = Date.parse(params[:business_date])
        @zone = arca_submission? ? :arca : :drawer
        # Only the drawer live row offers a supplier; the arca zone has none.
        @suppliers = supplier_options if @zone == :drawer
        return refuse("El día está cerrado.") if day_closed?
        return refuse("Esa categoría no se carga en esta zona.") unless zone_category?
        return refuse("Indicá si el socio retira o aporta.") unless partner_direction?

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
          supplier: submitted_supplier,
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

        @suppliers = supplier_options if @movement.drawer_zone?
        render :edit
      end

      def update
        load_movement
        authorize @movement
        deny_forbidden_category!
        return refuse_closed_day if day_closed?
        return refuse_edit("Esa categoría no se carga en esta zona.") unless zone_category?
        return refuse_edit("Indicá si el socio retira o aporta.") unless partner_direction?

        amount = signed_amount
        return refuse_edit("El monto no es un número.") if amount.nil?
        return refuse_edit("El monto no puede ser cero.") if zero_amount?(amount)

        drawer_zone_before = @movement.drawer_zone?
        saved = @movement.update(
          amount: amount,
          category: params[:category],
          subcategory: params[:subcategory].presence,
          channel: params[:channel].presence,
          account: account_for(params[:category], params[:channel]),
          supplier: submitted_supplier,
          description: params[:description].presence
        )

        return refuse_edit(@movement.errors.full_messages.join(", ")) unless saved

        @zone_changed = @movement.drawer_zone? != drawer_zone_before
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

      # The arca zone is the one that declares its arca; the drawer zone never
      # submits one.
      def arca_submission?
        params[:account].present?
      end

      def zone_category?
        policy(CashMovement).categories_for(arca_submission? ? :arca : :drawer).include?(params[:category])
      end

      # A category she may not load at all is a permission failure, not a row
      # she filled in wrong; the redirect says so.
      def deny_forbidden_category!
        raise Pundit::NotAuthorizedError if policy(CashMovement).forbidden_category?(params[:category])
      end

      def partner_direction?
        return true unless params[:category] == "partner"

        CashMovement::PARTNER_DIRECTION_LABELS.key?(params[:direction])
      end

      def day_closed?
        DailyClosing.exists?(business_date: @business_date)
      end

      # The single point the two zones diverge: the arca zone submits its arca,
      # the drawer zone derives it. A sale lands in the arca its channel implies;
      # an expense loaded in the drawer zone came out of the till by definition.
      def account_for(category, channel)
        return submitted_account if arca_submission?
        return "drawer" unless category == "sale"

        CashMovement::CHANNEL_ACCOUNTS[channel.to_s]
      end

      # Only a compensation sale names one. An id that matches nothing yields
      # nil, which the model rejects, the same way an unknown arca does.
      def submitted_supplier
        Supplier.find_by(id: params[:supplier_id])
      end

      # An unknown arca yields a nil account, which the model rejects, the same
      # way an unknown channel does.
      def submitted_account
        CashMovement::ACCOUNT_LABELS.key?(params[:account]) ? params[:account] : nil
      end

      def zero_amount?(decimal_string)
        BigDecimal(decimal_string).zero?
      end

      # The cashier types a bare amount; the category decides the sign.
      def signed_amount
        decimal = decimal_string_from(params[:amount])
        return nil if decimal.nil?

        outflow_submission? ? "-#{decimal.delete_prefix('-')}" : decimal
      end

      # partner is the one category that goes both ways, so the direction comes
      # from the named field beside it rather than from the category.
      def outflow_submission?
        return params[:direction] == "withdrawal" if params[:category] == "partner"

        OUTFLOW_CATEGORIES.include?(params[:category])
      end

      # A rejected correction keeps the form row on screen, with the reason, the
      # way a rejected load keeps the live row.
      def refuse_edit(message)
        @error = message
        @movement.restore_attributes
        @suppliers = supplier_options if @movement.drawer_zone?
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
