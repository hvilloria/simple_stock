# frozen_string_literal: true

module Inventory
  # Sets each product's stock to the number an admin counted. The difference
  # is taken at save time, under the product's row lock, against the sum of its
  # movements rather than the cached column, so the stock ends at the counted
  # number even if a sale landed in between or the cache had drifted.
  class SetCountedStock
    MAX_COUNT = 1_000_000

    def self.call(user:, note:, lines:)
      new(user: user, note: note, lines: lines).call
    end

    def initialize(user:, note:, lines:)
      @user  = user
      @note  = note.to_s.strip
      @lines = Array(lines)
    end

    def call
      validate!
      movements = ActiveRecord::Base.transaction do
        written = @lines.sort_by { |line| product_id(line) }.filter_map { |line| adjust(line) }
        raise ValidationError, "No hay cambios de stock para guardar" if written.empty?

        written
      end

      Result.new(success?: true, record: movements, errors: [])
    rescue ValidationError => e
      Result.new(success?: false, record: nil, errors: [ e.message ])
    rescue ActiveRecord::RecordNotFound
      Result.new(success?: false, record: nil, errors: [ "Producto no encontrado" ])
    rescue ActiveRecord::Deadlocked
      Result.new(success?: false, record: nil,
                 errors: [ "Otro movimiento de stock se guardó al mismo tiempo. Probá guardar el ajuste de nuevo." ])
    rescue StandardError => e
      Rails.logger.error("Error in Inventory::SetCountedStock: #{e.message}")
      Result.new(success?: false, record: nil, errors: [ "Error guardando el ajuste" ])
    end

    private

    class ValidationError < StandardError; end

    def validate!
      raise ValidationError, "El motivo es obligatorio" if @note.empty?
      raise ValidationError, "Agregá al menos un producto" if @lines.empty?

      seen = []
      @lines.each do |line|
        id = product_id(line)
        raise ValidationError, "Producto no encontrado" if id.nil?

        count = parse(line[:counted])
        raise ValidationError, "El stock real de #{label(id)} debe ser un número entero mayor o igual a 0" if count.nil? || count.negative?
        raise ValidationError, "El stock real de #{label(id)} es demasiado grande" if count > MAX_COUNT
        raise ValidationError, "#{label(id)} está repetido" if seen.include?(id)

        seen << id
      end
    end

    def adjust(line)
      product    = Product.lock.find(product_id(line))
      difference = parse(line[:counted]) - product.stock_movements.sum(:quantity)
      return if difference.zero?

      # AdjustStock's floor reads the cached column; the target here is the count, which is never negative.
      result = Inventory::AdjustStock.call(product: product, stock_location: location, movement_type: :adjustment,
                                           quantity: difference, note: @note, user: @user, allow_negative: true)
      raise ValidationError, result.errors.join(", ") if result.failure?

      result.record
    end

    def parse(raw)
      Integer(raw.to_s.strip, 10)
    rescue ArgumentError
      nil
    end

    def product_id(line)
      parse(line[:product_id])
    end

    def label(id)
      Product.find_by(id: id)&.name || "producto #{id}"
    end

    def location
      @location ||= StockLocation.first!
    end
  end
end
