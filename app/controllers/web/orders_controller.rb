module Web
  class OrdersController < ApplicationController
    before_action :load_products, only: [ :new, :create ]
    before_action :load_customers, only: [ :new, :create ]
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
      result = Sales::CreateOrder.call(
        customer: find_or_create_customer,
        items: parse_items,
        order_type: params[:order_type] || "cash",
        channel: params[:channel]
      )

      if result.success?
        redirect_to web_orders_path, notice: "Venta registrada exitosamente"
      else
        flash.now[:alert] = result.errors.join(", ")
        @order = Order.new
        render :new, status: :unprocessable_entity
      end
    end

    def cancel
      result = Sales::CancelOrder.call(
        order: @order,
        reason: params[:reason] || "Anulada desde interfaz"
      )

      if result.success?
        redirect_to web_orders_path, notice: "Venta anulada y stock reintegrado"
      else
        redirect_to web_orders_path, alert: result.errors.join(", ")
      end
    end

    private

    def load_products
      @products = Product.active.order(:name)
    end

    def load_customers
      @customers = Customer.order(:name)
    end

    def load_order
      @order = Order.find(params[:id])
    end

    def parse_items
      # Parsear items del form según estructura actual
      # Por ahora soportamos un solo producto
      product = Product.find(order_params[:product_id])
      quantity = order_params[:quantity].to_i

      [
        {
          product_id: product.id,
          quantity: quantity,
          unit_price: product.price_unit
        }
      ]
    end

    def find_or_create_customer
      # Si params[:customer_id] existe y no es 'mostrador', buscar customer
      # Si no existe o es 'mostrador', usar Customer.mostrador
      if params[:customer_id].present? && params[:customer_id] != "mostrador"
        Customer.find(params[:customer_id])
      else
        Customer.mostrador
      end
    end

    def order_params
      params.require(:order).permit(:product_id, :quantity, :customer_id, :order_type, :channel)
    end
  end
end
