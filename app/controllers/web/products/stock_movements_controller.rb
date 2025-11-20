module Web
    module Products
      class StockMovementsController < ApplicationController
        before_action :load_product
        before_action :load_stock_location

        def new
          @movement_type = params[:movement_type] || "purchase"
        end

      def create
        quantity = movement_quantity_param

        result = Inventory::AdjustStock.call(
          product:        @product,
          stock_location: @stock_location,
          movement_type:  movement_type_param.to_sym,
          quantity:       quantity,
          reference:      params[:reference],
          note:           params[:note]
        )

        if result.success?
          redirect_to web_products_path, notice: "Stock updated successfully."
        else
          flash.now[:alert] = result.errors.join(", ")
          @movement_type = movement_type_param
          render :new, status: :unprocessable_entity
        end
      rescue ArgumentError => e
        flash.now[:alert] = "Could not update stock: #{e.message}"
        @movement_type = movement_type_param
        render :new, status: :unprocessable_entity
      end

        private

        def load_product
          @product = Product.find(params[:product_id])
        end

        def load_stock_location
          @stock_location = StockLocation.first!
        end

        def movement_type_param
          params.require(:movement_type)
        end

        def movement_quantity_param
          raw = params.require(:quantity).to_i

          raise ArgumentError, "The quantity cannot be 0" if raw.zero?

          case movement_type_param
          when "purchase"
            raw.abs
          when "sale"
            -raw.abs
          when "adjustment"
            raw
          else
            raise ArgumentError, "Invalid movement type"
          end
        end
      end
    end
end
