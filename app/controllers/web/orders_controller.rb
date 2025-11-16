module Web
  class OrdersController < ApplicationController
    before_action :load_products, only: [ :new, :create ]
    before_action :load_order, only: [ :cancel ]

    def index
      @orders = Order
        .includes(:customer, order_items: :product)
        .order(created_at: :desc)
        .limit(50)
    end

    def new
      @order = Order.new
    end

    def create
      product = Product.find(order_params[:product_id])
      quantity = order_params[:quantity].to_i

      if quantity <= 0
        flash.now[:alert] = "The quantity must be greater than 0."
        @order = Order.new
        render :new, status: :unprocessable_entity
        return
      end

      @order = Sales::CreateOrder.call(
        customer: nil,
        lines: [
          {
            product:    product,
            quantity:   quantity,
            unit_price: product.price_unit
          }
        ]
      )

      redirect_to web_orders_path, notice: "Order registered successfully."
    rescue ArgumentError => e
      flash.now[:alert] = e.message
      @order = Order.new
      render :new, status: :unprocessable_entity
    end

    def cancel
      Sales::CancelOrder.call(order: @order, reason: "Cancelled from UI")

      redirect_to web_orders_path, notice: "Order cancelled and stock returned."
    rescue ArgumentError => e
      redirect_to web_orders_path, alert: e.message
    end

    private

    def load_products
      @products = Product.order(:name)
    end

    def load_order
      @order = Order.find(params[:id])
    end

    def order_params
      params.require(:order).permit(:product_id, :quantity)
    end
  end
end
