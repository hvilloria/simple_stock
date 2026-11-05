module Web
  class ProductsController < ApplicationController
    include CurrencyParser
    include ChannelPriceParams

    def index
      authorize Product
      @tab = params[:tab] == "combos" ? "combos" : "all"
      @active_combos_count = Product.combos.active.count
      @pagy, @products = pagy(@tab == "combos" ? combos_scope : products_scope)
    end

    def show
      @product = Product.find(params[:id])
      authorize @product
      if @product.combo?
        @combo_components = @product.combo_components.includes(:product).order(:id)
        @components_price_sum = @product.components_price_sum
      else
        @recent_movements = @product.stock_movements
                                    .order(created_at: :desc)
                                    .limit(10)
                                    .includes(:stock_location, :reference, :user)
      end
    end

    def new
      @product = Product.new(active: true, cost_currency: "USD")
      authorize @product
      @channel_price_values = channel_price_values_for(@product)
    end

    def create
      @product = Product.new
      authorize @product

      result = Products::Save.call(product: @product, attributes: sanitized_product_params,
                                   channel_prices: parsed_channel_prices)
      if result.success?
        redirect_to web_products_path, notice: "Producto creado exitosamente"
      else
        @channel_price_values = echoed_channel_price_values
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @product = Product.find(params[:id])
      authorize @product
      return redirect_to(edit_web_combo_path(@product)) if @product.combo?

      @channel_price_values = channel_price_values_for(@product)
    end

    def update
      @product = Product.find(params[:id])
      authorize @product
      return redirect_to(edit_web_combo_path(@product)) if @product.combo?

      result = Products::Save.call(product: @product, attributes: update_product_params,
                                   channel_prices: parsed_channel_prices)
      if result.success?
        redirect_to web_product_path(@product), notice: "Producto actualizado exitosamente"
      else
        @channel_price_values = echoed_channel_price_values
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @product = Product.find(params[:id])
      authorize @product

      if @product.destroy
        redirect_to web_products_path, notice: "Producto eliminado exitosamente"
      else
        redirect_to web_product_path(@product), alert: @product.errors.full_messages.to_sentence
      end
    end

    def search
      authorize Product, :search?
      scope = params[:include_combos] == "1" ? Product.active : Product.active.regular
      @products = scope.search(params[:q])
                       .includes(:channel_prices, combo_components: :product)
                       .order(:combo, :name)
                       .limit(10)

      render json: @products.map { |product|
        product.as_json(
          only: [ :id, :sku, :name, :price_unit, :current_stock, :brand, :origin, :product_type, :combo ],
          methods: [ :channel_prices_map ]
        ).merge("components" => product.search_components)
      }
    end

    private

    def products_scope
      Product.search(params[:q])
             .by_category(params[:category])
             .by_status(params[:status])
             .includes(combo_components: :product)
             .sorted_by(params[:sort], params[:direction])
    end

    def combos_scope
      scope = Product.combos.search(params[:q]).includes(combo_components: :product).order(:sku)
      case params[:combo_status]
      when "archived" then scope.inactive
      when "all" then scope
      else scope.active
      end
    end

    def product_params
      params.require(:product).permit(
        :sku, :name, :brand, :category, :product_type, :origin,
        :price_unit, :cost_unit, :cost_currency, :active
      )
    end

    def sanitized_product_params
      params_hash = product_params.to_h

      # Convert Argentine format to decimal for currency fields
      params_hash[:price_unit] = parse_amount(params_hash[:price_unit]) if params_hash[:price_unit].present?
      params_hash[:cost_unit] = parse_amount(params_hash[:cost_unit]) if params_hash[:cost_unit].present?

      params_hash
    end

    def update_product_params
      params_hash = params.require(:product).permit(
        :name, :brand, :category, :product_type, :origin,
        :price_unit, :cost_unit, :cost_currency, :active
      ).to_h

      params_hash[:price_unit] = parse_amount(params_hash[:price_unit]) if params_hash[:price_unit].present?
      params_hash[:cost_unit]  = parse_amount(params_hash[:cost_unit]) if params_hash[:cost_unit].present?

      params_hash
    end
  end
end
