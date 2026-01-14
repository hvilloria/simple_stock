module Web
  class OrdersController < ApplicationController
    before_action :load_products, only: [ :new, :create ]
    before_action :load_customers, only: [ :new, :create ]
    before_action :load_order, only: [ :show, :cancel ]

    def index
      authorize Order
      @orders = Order
        .includes(:customer, order_items: :product)
        .order(created_at: :desc)
        .limit(50)
    end

    def show
      authorize @order
      @order_items = @order.order_items.includes(:product)
      @stock_movements = @order.stock_movements.includes(:product, :stock_location).order(created_at: :desc)
    end

    def new
      @order = Order.new
      authorize @order

      # Contexto: viene desde product show con producto pre-seleccionado
      if params[:product_id].present?
        @preloaded_product = Product.active.find_by(id: params[:product_id])
        if @preloaded_product
          @order.order_items.build(
            product: @preloaded_product,
            quantity: 1,
            unit_price: @preloaded_product.price_unit
          )
        else
          flash.now[:alert] = "Producto no encontrado o inactivo"
          @order.order_items.build
        end
      else
        # Contexto: venta desde cero (búsqueda manual por ahora)
        @order.order_items.build
      end
    end

    def create
      authorize Order, :create?
      result = Sales::CreateOrder.call(
        customer: find_or_create_customer,
        items: parse_items,
        order_type: params[:order_type] || "cash",
        channel: params[:channel],
        source: params[:source] || "live",
        sale_date: params[:sale_date],
        paper_number: params[:paper_number]
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
      authorize @order, :cancel?
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
      # Solo cargar productos si NO viene product_id (para evitar cargar miles de productos innecesariamente)
      # En Fase 2, esto se reemplazará por búsqueda AJAX
      @products = params[:product_id].present? ? [] : Product.active.order(:name).limit(50)
    end

    def load_customers
      @customers = Customer.order(:name)
    end

    def load_order
      @order = Order.find(params[:id])
    end

    def parse_items
      # Parsear items desde purchase_items params
      return [] unless params[:purchase_items]

      params[:purchase_items].map do |item|
        {
          product_id: item[:product_id].to_i,
          quantity: item[:quantity].to_i,
          unit_price: item[:unit_price].present? ? item[:unit_price].to_f : nil # Permitir nil
        }
      end.reject { |item| item[:quantity] <= 0 }
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
      params.require(:order).permit(
        :customer_id,
        :order_type,
        :channel,
        order_items_attributes: [ :id, :product_id, :quantity, :_destroy ]
      )
    end
  end
end
