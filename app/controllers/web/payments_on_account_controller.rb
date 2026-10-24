module Web
  class PaymentsOnAccountController < ApplicationController
    helper_method :remaining_to_pay, :earned_discount, :outstanding_balance, :last_discount_percent, :cash_settle_amount

    def index
      authorize Order, :index?, policy_class: PaymentOnAccountPolicy
      @operations = Order.open_on_account
                         .includes(:customer, :user, order_items: :product)
                         .search_contact(params[:q])
                         .order(created_at: :desc)
    end

    def show
      @order = Order.on_account.includes(:user, order_items: :product, payment_allocations: :payment).find(params[:id])
      authorize @order, :show?, policy_class: PaymentOnAccountPolicy

      policy = PaymentOnAccountPolicy.new(current_user, @order)
      @can_deliver = policy.deliver?
      @can_collect = policy.collect?
      @can_edit_items = policy.edit_item?
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

    private

    def remaining_to_pay
      @remaining_to_pay ||= @order.remaining_to_pay
    end

    def earned_discount
      @earned_discount ||= @order.earned_discount
    end

    def outstanding_balance
      @outstanding_balance ||= @order.outstanding_balance
    end

    def last_discount_percent
      @last_discount_percent ||= @order.last_collection_discount_percent
    end

    def cash_settle_amount
      @cash_settle_amount ||= @order.cash_settle_amount(last_discount_percent)
    end
  end
end
