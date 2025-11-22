module Web
  class ProductsController < ApplicationController
    def index
      @products = Product.active.order(:name)
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

    private

    def product_params
      params.require(:product).permit(
        :sku, :name, :brand, :category, :product_type, :origin,
        :price_unit, :cost_unit, :cost_currency, :active
      )
    end
  end
end
