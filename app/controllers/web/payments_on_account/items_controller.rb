module Web
  module PaymentsOnAccount
    class ItemsController < ApplicationController
      before_action :set_order_and_item

      def edit
        authorize @order, :edit_item?, policy_class: PaymentOnAccountPolicy

        redirect_to web_payments_on_account_path(@order), alert: "El producto ya fue entregado" if @item.delivered_at.present?
      end

      def update
        authorize @order, :edit_item?, policy_class: PaymentOnAccountPolicy

        result = ::Sales::ReplaceOrderItem.call(
          order_item: @item,
          product_id: params[:product_id],
          quantity:   params[:quantity]
        )

        if result.success?
          redirect_to web_payments_on_account_path(@order), notice: "Producto actualizado"
        else
          redirect_to edit_web_payments_on_account_item_path(@order, @item),
                      alert: result.errors.join(", ")
        end
      end

      private

      def set_order_and_item
        @order = Order.on_account.find(params[:payments_on_account_id])
        @item  = @order.order_items.find(params[:id])
      end
    end
  end
end
