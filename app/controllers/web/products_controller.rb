module Web
  class ProductsController < ApplicationController
    include CurrencyParser

    def index
      authorize Product
      products_scope = Product.search(params[:q])
                              .by_category(params[:category])
                              .by_status(params[:status])
                              .sorted_by(params[:sort], params[:direction])
      @pagy, @products = pagy(products_scope)
    end

    def show
      @product = Product.find(params[:id])
      authorize @product
      @recent_movements = @product.stock_movements
                                  .order(created_at: :desc)
                                  .limit(10)
                                  .includes(:stock_location, :reference, :user)
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
      @channel_price_values = channel_price_values_for(@product)
    end

    def update
      @product = Product.find(params[:id])
      authorize @product

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

      @product.destroy
      redirect_to web_products_path, notice: "Producto eliminado exitosamente"
    end

    def search
      authorize Product, :search?
      @products = Product.active
                         .search(params[:q])
                         .includes(:channel_prices)
                         .limit(10)

      render json: @products.as_json(
        only: [ :id, :sku, :name, :price_unit, :current_stock, :brand, :origin, :product_type ],
        methods: [ :channel_prices_map ]
      )
    end

    private

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

    # Blank means remove the channel price; anything else is parsed, so
    # garbage reads as 0 and the model refuses it.
    def parsed_channel_prices
      return {} unless channel_prices_hash?

      submitted_channel_price_values.transform_values { |raw| raw.blank? ? nil : parse_amount(raw) }
    end

    def channel_prices_hash?
      !params.key?(:channel_prices) || params[:channel_prices].is_a?(ActionController::Parameters)
    end

    def submitted_channel_price_values
      return ProductChannelPrice::CHANNELS.index_with { "" } unless channel_prices_hash?

      raw = params.fetch(:channel_prices, {}).permit(*ProductChannelPrice::CHANNELS).to_h
      ProductChannelPrice::CHANNELS.index_with { |channel| raw[channel].to_s }
    end

    # Re-render values: a positive price is shown AR-formatted (the form's own
    # cleanup leaves dots that a later unformat would misread); anything else
    # is echoed as typed.
    def echoed_channel_price_values
      submitted_channel_price_values.to_h do |channel, raw|
        amount = parse_amount(raw)
        [ channel, amount&.positive? ? format_channel_price(amount) : raw ]
      end
    end

    def format_channel_price(amount)
      helpers.number_with_precision(amount, precision: 2, delimiter: ".", separator: ",")
    end

    def channel_price_values_for(product)
      ProductChannelPrice::CHANNELS.index_with do |channel|
        price = product.channel_price_for(channel)&.price
        price ? format_channel_price(price) : ""
      end
    end
  end
end
