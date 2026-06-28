module Web
  class PaymentsOnAccountController < ApplicationController
    def index
      authorize Order, :index?, policy_class: PaymentOnAccountPolicy
      @operations = Order.open_on_account
                         .includes(:customer, order_items: :product)
                         .search_contact(params[:q])
                         .order(created_at: :desc)
    end

    def show
      @order = Order.on_account.includes(order_items: :product).find(params[:id])
      authorize @order, :show?, policy_class: PaymentOnAccountPolicy

      policy = PaymentOnAccountPolicy.new(current_user, @order)
      @can_deliver = policy.deliver?
      @can_collect = policy.collect?
    end

    def deliver
      @order = Order.on_account.find(params[:id])
      authorize @order, :deliver?, policy_class: PaymentOnAccountPolicy

      result = Inventory::MarkDelivered.call(
        order:          @order,
        order_item_ids: Array(params[:order_item_ids]),
        delivered:      true
      )

      if result.success?
        redirect_to web_payments_on_account_path(@order), notice: "Entrega registrada"
      else
        redirect_to web_payments_on_account_path(@order), alert: result.errors.join(", ")
      end
    end
  end
end
