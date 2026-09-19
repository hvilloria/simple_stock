module Web
  module PaymentsOnAccount
    class PaymentsController < ApplicationController
      before_action :set_order

      def new
        authorize @order, :collect?, policy_class: PaymentOnAccountPolicy
      end

      def create
        authorize @order, :collect?, policy_class: PaymentOnAccountPolicy

        result = ::Payments::CollectOnAccount.call(
          order:            @order,
          amount_to_settle: parse_amount(params[:amount_to_settle]),
          discount_percent: params[:discount_percent].to_i,
          tenders:          parsed_tenders
        )

        if result.success?
          redirect_to web_payments_on_account_path(@order), notice: "Cobro registrado"
        else
          flash.now[:alert] = result.errors.join(", ")
          render :new, status: :unprocessable_entity
        end
      end

      private

      def set_order
        @order = Order.on_account.find(params[:payments_on_account_id])
      end

      # Tenders arrive as `tenders[0][payment_method]=cash&tenders[0][amount]=1.500,00`.
      # Their sum must match the cash to collect; the service enforces that.
      def parsed_tenders
        rows = params[:tenders]
        return [] if rows.blank?

        rows.to_unsafe_h.values.filter_map do |row|
          amount = parse_amount(row[:amount])
          next if amount <= 0
          { payment_method: row[:payment_method], amount: amount }
        end
      end

      # Strip Argentine formatting (1.500,00 -> 1500.00) before to_f.
      def parse_amount(raw)
        raw.to_s.gsub(".", "").tr(",", ".").to_f
      end
    end
  end
end
