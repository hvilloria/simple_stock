# frozen_string_literal: true

require "csv"

module Inventory
  # Sincroniza productos y stock desde archivo CSV
  #
  # Procesa un archivo CSV fila por fila:
  # - Para productos nuevos: crea el producto y su stock inicial vía StockMovement
  # - Para productos existentes: actualiza precio y ajusta stock vía StockMovement
  #
  # Reglas de negocio:
  # - Todos los SKUs en CSV terminan en -IMP, se guardan sin ese sufijo
  # - Todos los productos son aftermarket
  # - Stock nunca puede ser negativo
  # - Precio de venta debe ser >= 0
  #
  # Uso:
  #   result = Inventory::SyncFromCsv.call(file_path: '/path/to/file.csv')
  #   if result.success?
  #     puts "Procesados: #{result.record[:stats][:created]} creados, #{result.record[:stats][:updated]} actualizados"
  #     puts "Log: #{result.record[:log_path]}"
  #   end
  class SyncFromCsv
    def self.call(file_path:, user: nil)
      new(file_path: file_path, user: user).call
    end

    def initialize(file_path:, user: nil)
      @file_path = file_path
      @user = user
      @stats = {
        created: 0,
        updated: 0,
        errors: 0,
        movements: 0,
        skipped: 0
      }
      @errors = []
      @log_entries = []
      @start_time = Time.current
    end

    def call
      setup_log
      log_header

      # Count total rows (excluding header)
      total_rows = CSV.read(@file_path, headers: true, encoding: "UTF-8").length

      log_info("Processing #{total_rows} products from CSV")
      puts "📦 Procesando #{total_rows} productos...\n\n"

      stock_location = StockLocation.first!

      # Process CSV file
      CSV.foreach(@file_path, headers: true, encoding: "UTF-8") do |row|
        process_row(row, stock_location)
      end

      log_summary
      print_console_summary
      save_log_file

      Result.new(
        success?: @stats[:errors] == 0,
        record: {
          stats: @stats,
          log_path: @log_path
        },
        errors: @errors
      )
    rescue StandardError => e
      log_error("FATAL ERROR", e.message)
      Rails.logger.error("Error in SyncFromCsv: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      save_log_file

      Result.new(
        success?: false,
        record: { stats: @stats, log_path: @log_path },
        errors: [ @errors + [ e.message ] ].flatten
      )
    end

    private

    # ============================================
    # PROCESSING
    # ============================================

    def process_row(row, stock_location)
      # Parse row data - CSV headers: ID del artículo, Nombre del artículo, Compatibilidad, etc.
      sku_raw = row[0]&.strip
      nombre = row[1]&.strip
      _compatibilidad = row[2]
      costo_usd = parse_decimal(row[3])
      precio_ars = parse_decimal(row[4])
      stock_excel = parse_integer(row[5])
      origen_code = row[7]&.strip

      # Validations
      # Skip rows without SKU or name silently
      unless sku_raw.present? && nombre.present?
        @stats[:skipped] += 1
        return
      end

      unless stock_excel >= 0
        log_error(sku_raw, "Stock cannot be negative (value: #{stock_excel})")
        return
      end

      unless precio_ars >= 0
        log_error(sku_raw, "Price cannot be negative (value: #{precio_ars})")
        return
      end

      # Clean SKU (remove -IMP suffix)
      sku = sku_raw.gsub(/-IMP$/i, "")

      # Map origin
      origin = map_origin(origen_code)

      # Find or create product
      # Buscar por SKU + product_type aftermarket (ya que todos son aftermarket)
      product = Product.find_by(sku: sku, product_type: "aftermarket")

      if product
        update_existing_product(product, precio_ars, stock_excel, stock_location)
      else
        create_new_product(sku, nombre, origin, costo_usd, precio_ars, stock_excel, stock_location)
      end

    rescue StandardError => e
      log_error(sku_raw || "UNKNOWN", "Unexpected error: #{e.message}")
    end

    def create_new_product(sku, nombre, origin, costo_usd, precio_ars, stock_excel, stock_location)
      product = Product.create!(
        sku: sku,
        name: nombre,
        product_type: "aftermarket",
        origin: origin,
        brand: nil,
        category: nil,
        cost_unit: costo_usd > 0 ? costo_usd : nil,
        cost_currency: "USD",
        price_unit: precio_ars,
        current_stock: 0,
        active: true
      )

      @stats[:created] += 1

      log_success("CREATED", sku, {
        name: nombre,
        origin: origin || "N/A",
        cost: costo_usd > 0 ? format_usd(costo_usd) : "N/A",
        price: format_ars(precio_ars),
        stock: "#{stock_excel} units"
      })

      puts "✅ #{sku} → Creado"

      # Create initial stock if any
      if stock_excel > 0
        movement = create_stock_movement(
          product: product,
          stock_location: stock_location,
          quantity: stock_excel,
          note: "Initial stock from CSV import"
        )

        if movement
          log_info("  Movement: ##{movement.id} (adjustment, +#{stock_excel})")
          puts "   📦 Stock inicial: #{stock_excel}"
        end
      end
    end

    def update_existing_product(product, nuevo_precio, stock_excel, stock_location)
      changes = []

      # Check price change
      precio_cambio = product.price_unit != nuevo_precio
      old_price = product.price_unit

      if precio_cambio
        product.update!(price_unit: nuevo_precio)
        price_diff = nuevo_precio - old_price
        changes << "Price: #{format_ars(old_price)} → #{format_ars(nuevo_precio)} (#{price_diff > 0 ? '+' : ''}#{format_ars(price_diff)})"
      end

      # Calculate stock difference
      stock_actual = product.current_stock
      diff_stock = stock_excel - stock_actual

      # Adjust stock if different
      if diff_stock != 0
        movement = create_stock_movement(
          product: product,
          stock_location: stock_location,
          quantity: diff_stock,
          note: "Stock adjustment from CSV import"
        )

        if movement
          changes << "Stock: #{stock_actual} → #{stock_excel} (#{diff_stock > 0 ? '+' : ''}#{diff_stock} units)"

          @stats[:updated] += 1

          log_update("UPDATED", product.sku, {
            name: product.name,
            changes: changes
          })

          puts "🔄 #{product.sku} → Actualizado"
          changes.each { |change| puts "   #{change}" }
        end
      elsif precio_cambio
        @stats[:updated] += 1

        log_update("UPDATED", product.sku, {
          name: product.name,
          changes: changes,
          note: "Stock unchanged (#{stock_actual} units)"
        })

        puts "🔄 #{product.sku} → Precio actualizado"
      else
        @stats[:skipped] += 1
      end
    end

    def create_stock_movement(product:, stock_location:, quantity:, note:)
      result = Inventory::AdjustStock.call(
        product: product,
        stock_location: stock_location,
        movement_type: :adjustment,
        quantity: quantity,
        reference: nil,
        note: note
      )

      if result.success?
        @stats[:movements] += 1
        result.record
      else
        log_error(product.sku, "Stock movement failed: #{result.errors.join(', ')}")
        nil
      end
    end

    # ============================================
    # HELPERS
    # ============================================

    def map_origin(code)
      case code&.upcase
      when "JAP" then "japan"
      when "TAI" then "taiwan"
      when "CHI" then "china"
      else nil
      end
    end

    def parse_decimal(value)
      return 0.0 if value.nil? || value.empty?
      # Remove currency symbols and formatting
      cleaned = value.to_s.gsub(/[$,]/, "").strip
      cleaned.to_f.round(2)
    end

    def parse_integer(value)
      return 0 if value.nil? || value.to_s.empty?
      value.to_s.gsub(/[,.]/, "").to_i
    end

    def format_usd(amount)
      "$#{amount.round(2)} USD"
    end

    def format_ars(amount)
      "$#{amount.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1.').reverse} ARS"
    end

    # ============================================
    # LOGGING
    # ============================================

    def setup_log
      timestamp = @start_time.strftime("%Y-%m-%d_%H-%M-%S")
      @log_path = Rails.root.join("log", "inventory_sync_#{timestamp}.log")
    end

    def log_header
      @log_entries << "=" * 80
      @log_entries << "INVENTORY SYNC FROM CSV"
      @log_entries << "=" * 80
      @log_entries << "Started at: #{@start_time.strftime('%Y-%m-%d %H:%M:%S %z')}"
      @log_entries << "File: #{@file_path}"
      @log_entries << "User: #{@user&.email || 'Console'}"
      @log_entries << ""
    end

    def log_info(message)
      timestamp = Time.current.strftime("%H:%M:%S")
      @log_entries << "[#{timestamp}] ℹ️  #{message}"
    end

    def log_success(action, sku, details)
      timestamp = Time.current.strftime("%H:%M:%S")
      @log_entries << ""
      @log_entries << "[#{timestamp}] ✅ #{action}: #{sku}"
      details.each do |key, value|
        @log_entries << "  #{key.to_s.capitalize}: #{value}"
      end
    end

    def log_update(action, sku, details)
      timestamp = Time.current.strftime("%H:%M:%S")
      @log_entries << ""
      @log_entries << "[#{timestamp}] 🔄 #{action}: #{sku}"
      @log_entries << "  Name: #{details[:name]}"

      if details[:changes].present?
        @log_entries << "  Changes:"
        details[:changes].each do |change|
          @log_entries << "    - #{change}"
        end
      end

      @log_entries << "  Note: #{details[:note]}" if details[:note]
    end

    def log_error(sku, message)
      timestamp = Time.current.strftime("%H:%M:%S")
      @stats[:errors] += 1
      @errors << "#{sku}: #{message}"

      @log_entries << ""
      @log_entries << "[#{timestamp}] ⚠️  ERROR: #{sku}"
      @log_entries << "  Reason: #{message}"

      puts "⚠️  ERROR: #{sku} → #{message}"
    end

    def log_summary
      duration = Time.current - @start_time
      minutes = (duration / 60).to_i
      seconds = (duration % 60).to_i

      @log_entries << ""
      @log_entries << "-" * 80
      @log_entries << "SUMMARY"
      @log_entries << "-" * 80
      @log_entries << "Completed at: #{Time.current.strftime('%Y-%m-%d %H:%M:%S %z')}"
      @log_entries << "Duration: #{minutes} minutes #{seconds} seconds"
      @log_entries << ""
      @log_entries << "Results:"
      @log_entries << "  ✅ Created: #{@stats[:created]} products"
      @log_entries << "  🔄 Updated: #{@stats[:updated]} products"
      @log_entries << "  ⏭️  Skipped: #{@stats[:skipped]} products (no changes)"
      @log_entries << "  ⚠️  Errors: #{@stats[:errors]} products"
      @log_entries << "  📈 Stock Movements: #{@stats[:movements]}"
      @log_entries << ""
      @log_entries << "Inventory Stats:"
      @log_entries << "  📦 Total products: #{Product.count}"
      @log_entries << "  📊 Total stock: #{Product.sum(:current_stock)} units"

      valor_inventario = Product.where.not(price_unit: nil).sum("current_stock * price_unit")
      @log_entries << "  💰 Inventory value: #{format_ars(valor_inventario)}"

      if @errors.any?
        @log_entries << ""
        @log_entries << "Errors detail:"
        @errors.each_with_index do |error, i|
          @log_entries << "  #{i + 1}. #{error}"
        end
      end

      @log_entries << ""
      @log_entries << "=" * 80
      @log_entries << "END OF LOG"
      @log_entries << "=" * 80
    end

    def print_console_summary
      puts "\n" + "━" * 60
      puts "📊 RESUMEN:"
      puts "  ✅ Productos creados: #{@stats[:created]}"
      puts "  🔄 Productos actualizados: #{@stats[:updated]}"
      puts "  ⏭️  Productos sin cambios: #{@stats[:skipped]}"
      puts "  ⚠️  Errores: #{@stats[:errors]}"
      puts "  📈 Stock Movements: #{@stats[:movements]}"
      puts ""
      puts "  📦 Total productos: #{Product.count}"
      puts "  📊 Stock total: #{Product.sum(:current_stock)} unidades"

      valor_inventario = Product.where.not(price_unit: nil).sum("current_stock * price_unit")
      puts "  💰 Valor inventario: #{format_ars(valor_inventario)}"
      puts "━" * 60
    end

    def save_log_file
      File.write(@log_path, @log_entries.join("\n"))
    end
  end
end
