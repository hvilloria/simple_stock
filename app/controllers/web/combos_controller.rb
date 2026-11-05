module Web
  class CombosController < ApplicationController
    include CurrencyParser
    include ChannelPriceParams

    before_action :set_combo, only: [ :edit, :update, :archive, :reactivate ]

    def new
      @combo = Product.new(active: true)
      authorize @combo, :create_combo?
      @channel_price_values = channel_price_values_for(@combo)
      prepare_components(current_component_rows)
    end

    def create
      @combo = Product.new(active: true)
      authorize @combo, :create_combo?

      result = save_combo
      if result.success?
        redirect_to web_product_path(@combo), notice: "Combo creado"
      else
        render_failure(:new, result)
      end
    end

    def edit
      authorize @combo
      @channel_price_values = channel_price_values_for(@combo)
      prepare_components(current_component_rows)
    end

    def update
      authorize @combo

      result = save_combo
      if result.success?
        redirect_to web_product_path(@combo), notice: "Combo actualizado"
      else
        render_failure(:edit, result)
      end
    end

    def archive
      change_active(false, "Combo archivado")
    end

    def reactivate
      change_active(true, "Combo reactivado")
    end

    private

    def set_combo
      @combo = Product.combos.find(params[:id])
    end

    def save_combo
      Combos::Save.call(combo: @combo, attributes: combo_attributes,
                        components: submitted_components, channel_prices: parsed_channel_prices)
    end

    def change_active(active, notice)
      authorize @combo, :archive?

      result = Combos::Save.call(combo: @combo, attributes: { active: active })
      if result.success?
        redirect_to web_product_path(@combo), notice: notice
      else
        redirect_to web_product_path(@combo), alert: result.errors.join(" · ")
      end
    end

    def render_failure(template, result)
      flash.now[:alert] = "No se pudo guardar el combo: #{result.errors.join(' · ')}"
      @channel_price_values = echoed_channel_price_values
      prepare_components(submitted_component_rows || current_component_rows)
      render template, status: :unprocessable_entity
    end

    def combo_attributes
      attributes = params.require(:combo).permit(:name, :price_unit).to_h
      attributes[:price_unit] = parse_amount(attributes[:price_unit]) if attributes.key?(:price_unit)
      attributes
    end

    # A combo with sales shows its parts read-only and posts none, so a missing
    # list leaves them untouched; for any other combo it means "no parts".
    def submitted_components
      rows = submitted_component_params
      return rows if rows

      components_editable? ? [] : nil
    end

    def submitted_component_params
      rows = params[:components]
      return unless rows.is_a?(Array)

      rows.select { |row| row.respond_to?(:permit) }.map { |row| row.permit(:product_id, :quantity).to_h }
    end

    def components_editable?
      @combo.new_record? || !@combo.has_sales?
    end

    def current_component_rows
      @combo.combo_components.includes(:product).map { |row| [ row.product, row.quantity ] }
    end

    def submitted_component_rows
      rows = submitted_component_params
      return unless rows

      products = Product.with_deleted.where(id: rows.map { |row| row["product_id"] }).index_by(&:id)
      rows.filter_map do |row|
        product = products[row["product_id"].to_i]
        [ product, row["quantity"].to_i ] if product
      end
    end

    def prepare_components(rows)
      @components_editable = components_editable?
      @component_items = rows.map do |product, quantity|
        { id: product.id, sku: product.sku, name: product.name, brand: product.brand,
          price_unit: product.price_unit.to_f, quantity: quantity }
      end
    end
  end
end
