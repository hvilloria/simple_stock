module Web
  class OrdersController < ApplicationController
    before_action :load_products, only: [ :new, :create ]
    before_action :load_customers, only: [ :new, :create ]
    before_action :load_order, only: [ :show, :cancel ]

    helper_method :search_mode?

    def index
      authorize Order

      @search = params[:paper_number].to_s.strip
      @type   = params[:type].to_s
      @status = normalize_status(search_mode? ? "" : (params[:status] || "confirmed"))
      @period = params[:period].presence || "this_week"
      @from, @to = resolve_period

      @pagy, @orders = pagy(filtered_orders)
    end

    def show
      authorize @order
      @order_items = @order.order_items.includes(:product)
      @stock_movements = @order.stock_movements.includes(:product, :stock_location).order(created_at: :desc)
    end

    def new
      @order = Order.new
      authorize @order

      # Context: comes from product show with a pre-selected product
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
      elsif params[:purchase_items].present?
        # Context: comes from the cart in the products listing
        params[:purchase_items].each do |item|
          product = Product.active.find_by(id: item[:product_id])
          next unless product
          @order.order_items.build(
            product: product,
            quantity: item[:quantity].to_i,
            unit_price: product.price_unit
          )
        end
      else
        # Context: sale from scratch (manual search for now)
        @order.order_items.build
      end
    end

    def create
      authorize Order, :create?
      result = Sales::CreateOrder.call(
        customer: find_or_create_customer,
        items: parse_items,
        order_type: params.dig(:order, :order_type) || "immediate",
        channel: params.dig(:order, :channel),
        source: params[:source] || "live",
        sale_date: params[:sale_date],
        paper_number: params[:paper_number],
        contact_name: params[:contact_name],
        contact_phone: params[:contact_phone],
        delivered_product_ids: Array(params[:delivered_product_ids]),
        user: current_user
      )

      if result.success?
        redirect_to web_order_path(result.record),
                    notice: "Nota #{result.record.paper_number} creada — pendiente de cobro"
      else
        flash.now[:alert] = result.errors.join(", ")
        @order = Order.new
        render :new, status: :unprocessable_entity
      end
    end

    def cancel
      policy_method = @order.pending_status? ? :cancel_pending? : :cancel?
      authorize @order, policy_method
      result = Sales::CancelOrder.call(
        order: @order,
        reason: params[:reason] || "Anulada desde interfaz"
      )

      if result.success?
        redirect_to web_orders_path, notice: "Venta anulada"
      else
        redirect_to web_orders_path, alert: result.errors.join(", ")
      end
    end

    private

    def search_mode?
      params[:paper_number].present?
    end

    def normalize_status(status)
      Order.statuses.key?(status) ? status : ""
    end

    def filtered_orders
      base = Order.includes(:customer, order_items: :product)
      return base.search_paper(@search).order(sale_date: :desc, id: :desc) if search_mode?

      scoped = base.by_type(@type).by_status_filter(@status)

      case @status
      when "confirmed"
        scoped.settled_between(@from, @to)
              .order(Arel.sql("settled_on DESC NULLS LAST, id DESC"))
      when "pending", "cancelled"
        scoped.sold_between(@from, @to).order(sale_date: :desc, id: :desc)
      else
        scoped.order(sale_date: :desc, id: :desc)
      end
    end

    # Todas and search mode deliberately return no range: they are the modes
    # whose purpose is not to narrow.
    def resolve_period
      return [ nil, nil ] if @status.blank?

      case @period
      when "today"      then [ Date.current, Date.current ]
      when "this_month" then [ Date.current.beginning_of_month, Date.current.end_of_month ]
      else [ Date.current.beginning_of_week(:monday), Date.current.end_of_week(:monday) ]
      end
    end

    def load_products
      # Only load products if neither product_id nor purchase_items is present (to avoid
      # loading thousands of products unnecessarily when the form is pre-filled).
      # In Phase 2, this will be replaced by AJAX search
      skip_load = params[:product_id].present? || params[:purchase_items].present?
      @products = skip_load ? [] : Product.active.order(:name).limit(50)
    end

    def load_customers
      @customers = Customer.order(:name)
    end

    def load_order
      @order = Order.includes(order_items: :product, stock_movements: [ :product, :stock_location ], payment_allocations: :payment).find(params[:id])
    end

    def parse_items
      # Parse items from purchase_items params
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
      customer_id = params.dig(:order, :customer_id)
      if customer_id.present? && customer_id != "mostrador"
        Customer.find(customer_id)
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
