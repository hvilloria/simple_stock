# frozen_string_literal: true

module Combos
  # Saves a combo: header and channel prices through Products::Save, plus its
  # components. A nil components list leaves the current ones untouched.
  class Save
    MIN_UNITS = 2

    def self.call(combo:, attributes:, components: nil, channel_prices: {})
      new(combo: combo, attributes: attributes, components: components, channel_prices: channel_prices).call
    end

    def initialize(combo:, attributes:, components:, channel_prices:)
      @combo          = combo
      @attributes     = attributes.to_h
      @components     = components&.map { |row| normalize(row) }
      @components   ||= [] if combo.new_record?
      @channel_prices = channel_prices
    end

    def call
      @combo.assign_attributes(@attributes)
      errors = validation_errors
      return failure(errors) if errors.any?

      result = nil
      ActiveRecord::Base.transaction do
        @combo.assign_attributes(combo: true, current_stock: 0, sku: Product.next_combo_sku) if @combo.new_record?
        result = Products::Save.call(product: @combo, attributes: @attributes, channel_prices: @channel_prices)
        raise ActiveRecord::Rollback if result.failure?

        replace_components if @components
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages)
    end

    private

    def normalize(row)
      row = row.to_h.symbolize_keys
      { product_id: row[:product_id].to_i, quantity: row[:quantity].to_i }
    end

    def validation_errors
      errors = []
      errors.concat(component_errors) if @components
      errors.concat(reactivation_errors) if reactivating?
      errors << "El precio de venta debe ser mayor a 0" unless @combo.price_unit.to_d.positive?
      errors.uniq
    end

    def component_errors
      errors = []
      errors << "El combo necesita al menos 2 unidades en total" if @components.sum { |row| row[:quantity] } < MIN_UNITS
      errors << "Una pieza no puede repetirse en el combo" if product_ids.uniq.size != product_ids.size

      products = Product.with_deleted.where(id: product_ids).index_by(&:id)
      product_ids.each do |id|
        product = products[id]
        if product.nil?
          errors << "Pieza inválida"
        elsif product.combo?
          errors << "Un combo no puede incluir otro combo"
        elsif unavailable?(product) && !reactivating?
          errors << "La pieza #{product.sku} no está activa"
        end
      end

      errors << locked_components_message if components_locked?
      errors
    end

    def reactivation_errors
      products = @components ? Product.with_deleted.where(id: product_ids).regular : @combo.components.with_deleted
      products.select { |product| unavailable?(product) }.map do |product|
        "No se puede reactivar: la pieza #{product.sku} está archivada. Reactivarla primero o crear un combo nuevo."
      end
    end

    def components_locked?
      return false if @combo.new_record? || !@combo.has_sales?

      @components.to_h { |row| [ row[:product_id], row[:quantity] ] } !=
        @combo.combo_components.to_h { |row| [ row.product_id, row.quantity ] }
    end

    def locked_components_message
      "Las piezas no se pueden cambiar porque el combo ya tiene ventas. " \
        "Para cambiarlas, archivar este combo y crear uno nuevo."
    end

    def reactivating?
      @combo.persisted? && @combo.will_save_change_to_active?(from: false, to: true)
    end

    def unavailable?(product)
      !product.active? || product.deleted_at.present?
    end

    def product_ids
      @product_ids ||= @components.map { |row| row[:product_id] }
    end

    def replace_components
      ComboComponent.where(combo_id: @combo.id).delete_all
      @components.each { |row| @combo.combo_components.create!(row) }
      @combo.combo_components.reset
    end

    def failure(messages)
      messages.each { |message| @combo.errors.add(:base, message) }
      Result.new(success?: false, record: @combo, errors: messages)
    end
  end
end
