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

    result = Sales::CreateOrder.call(
      customer: nil,
      lines: [
        {
          product:    product,
          quantity:   quantity,
          unit_price: product.price_unit
        }
      ]
    )

    if result.success?
      redirect_to web_orders_path, notice: "Order registered successfully."
    else
      flash.now[:alert] = result.errors.join(", ")
      @order = Order.new
      render :new, status: :unprocessable_entity
    end
  end

  def cancel
    result = Sales::CancelOrder.call(order: @order, reason: "Cancelled from UI")

    if result.success?
      redirect_to web_orders_path, notice: "Order cancelled and stock returned."
    else
      redirect_to web_orders_path, alert: result.errors.join(", ")
    end
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
