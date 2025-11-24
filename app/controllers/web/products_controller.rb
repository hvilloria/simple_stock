module Web
  class ProductsController < ApplicationController
    def index
      @products = Product.search(params[:q])
                         .by_category(params[:category])
                         .by_status(params[:status])
                         .order(:name)
    end

    def show
      @product = Product.find(params[:id])
      @recent_movements = @product.stock_movements
                                  .order(created_at: :desc)
                                  .limit(10)
                                  .includes(:stock_location, :reference)
    end

    def new
      @product = Product.new(active: true, cost_currency: "USD")
    end

    def create
      @product = Product.new(product_params)

      if @product.save
        redirect_to web_products_path, notice: "Producto creado exitosamente"
      else
        render :new, status: :unprocessable_entity
      end
    end

    def search
      @products = Product.active
                         .search(params[:q])
                         .limit(10)

      render json: @products.as_json(
        only: [ :id, :sku, :name, :price_unit, :current_stock, :brand, :origin, :product_type ],
        methods: []
      )
    end

    private

    def product_params
      params.require(:product).permit(
        :sku, :name, :brand, :category, :product_type, :origin,
        :price_unit, :cost_unit, :cost_currency, :active
      )
    end
  end
end
