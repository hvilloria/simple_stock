# frozen_string_literal: true

module Web
  class StockAdjustmentsController < ApplicationController
    def new
      authorize Product, :adjust_stock?
      origin = Product.find_by(id: params[:product_id])
      @lines = origin ? [ line_for(origin, "") ] : []
      @back_path = back_path
    end

    def create
      authorize Product, :adjust_stock?
      result = Inventory::SetCountedStock.call(user: current_user, note: params[:note], lines: submitted_lines)

      if result.success?
        redirect_to new_web_stock_adjustment_path, notice: saved_notice(result.record.size)
      else
        flash.now[:alert] = result.errors.join(", ")
        @lines = redisplayed_lines
        @note = params[:note]
        @back_path = back_path
        render :new, status: :unprocessable_entity
      end
    end

    private

    def submitted_lines
      return [] unless params[:lines].respond_to?(:to_unsafe_h)

      params[:lines].to_unsafe_h.values.filter_map do |row|
        next unless row.is_a?(Hash)

        { product_id: row["product_id"].to_s, counted: row["counted"].to_s }
      end
    end

    def redisplayed_lines
      products = Product.where(id: submitted_lines.map { |line| line[:product_id] }).index_by { |product| product.id.to_s }
      submitted_lines.filter_map do |line|
        product = products[line[:product_id]]
        line_for(product, line[:counted]) if product
      end
    end

    def line_for(product, counted)
      { product_id: product.id, sku: product.sku, name: product.name, brand: product.brand.to_s,
        current_stock: product.current_stock, counted: counted }
    end

    def back_path
      origin = Product.find_by(id: params[:product_id])
      origin ? web_product_path(origin) : web_products_path
    end

    def saved_notice(count)
      "Ajuste guardado: #{count} #{count == 1 ? 'producto actualizado' : 'productos actualizados'}"
    end
  end
end
