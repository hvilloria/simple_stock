module Web
  module PaymentsOnAccount
    class PaymentsController < ApplicationController
      before_action :set_order

      def new
        authorize @order, :collect?, policy_class: PaymentOnAccountPolicy
      end

      def create
        authorize @order, :collect?, policy_class: PaymentOnAccountPolicy

        amount   = parse_amount(params[:amount_to_settle]).to_d
        discount = params[:discount_percent].to_i
        cash_raw = amount - (amount * discount / 100).round(2)
        # Discounted cash collections round UP to the next hundred (must match
        # Payments::CollectOnAccount#cash_to_collect so validation passes).
        cash     = discount.positive? ? (cash_raw / 100.0).ceil * 100 : cash_raw

        result = ::Payments::CollectOnAccount.call(
          order:            @order,
          amount_to_settle: amount,
          discount_percent: discount,
          tenders:          [ { payment_method: params[:payment_method], amount: cash } ]
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

      def parse_amount(raw)
        raw.to_s.gsub(".", "").tr(",", ".").to_f
      end
    end
  end
end
