module Web
  class ProductsController < ApplicationController
    include CurrencyParser

    MONEY_FIELDS = %i[price_unit cost_unit].freeze

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
                                  .includes(:stock_location, :reference)
    end

    def new
      @product = Product.new(active: true, cost_currency: "USD")
      authorize @product
    end

    def create
      attributes = product_params.to_h
      invalid_amounts = parse_money_fields!(attributes)

      @product = Product.new(attributes)
      authorize @product

      if invalid_amounts.any?
        reject_invalid_amounts(invalid_amounts)
        render :new, status: :unprocessable_entity
      elsif @product.save
        redirect_to web_products_path, notice: "Producto creado exitosamente"
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @product = Product.find(params[:id])
      authorize @product
    end

    def update
      @product = Product.find(params[:id])
      authorize @product

      attributes = update_product_params.to_h
      invalid_amounts = parse_money_fields!(attributes)

      if invalid_amounts.any?
        @product.assign_attributes(attributes)
        reject_invalid_amounts(invalid_amounts)
        render :edit, status: :unprocessable_entity
      elsif @product.update(attributes)
        redirect_to web_product_path(@product), notice: "Producto actualizado exitosamente"
      else
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

    def update_product_params
      params.require(:product).permit(
        :name, :brand, :category, :product_type, :origin,
        :price_unit, :cost_unit, :cost_currency, :active
      )
    end

    # Converts the money fields in place and returns the ones that were filled in but
    # could not be parsed. A blank field is legitimate (nil price), an unparseable one
    # is dropped from the hash so ActiveRecord's decimal cast cannot turn it into 0.0.
    def parse_money_fields!(attributes)
      MONEY_FIELDS.select do |field|
        next false if attributes[field].blank?

        amount = parse_amount(attributes[field])
        if amount.nil?
          attributes.delete(field)
          true
        else
          attributes[field] = amount
          false
        end
      end
    end

    def reject_invalid_amounts(fields)
      @product.valid?
      fields.each { |field| @product.errors.add(field, "no es un monto válido") }
    end
  end
end
