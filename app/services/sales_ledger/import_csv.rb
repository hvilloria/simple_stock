# frozen_string_literal: true

require "csv"
require "digest"

module SalesLedger
  # Importa ventas históricas desde un archivo CSV al sales ledger.
  #
  # Uso:
  #   result = SalesLedger::ImportCsv.call(file: uploaded_file, filename: "enero.csv")
  #   result.success?  # => true / false
  #   result.record    # => instancia SalesLedger::SalesImport con métricas del lote
  #   result.errors    # => array de strings (solo errores fatales que abortaron el lote)
  #
  # IMPORTANTE: este servicio NO toca orders, order_items, stock_movements ni payments.
  class ImportCsv
    REQUIRED_COLUMNS = %w[sale_date ticket_number oem_code product_name quantity unit_price].freeze

    def self.call(file:, filename: nil)
      new(file: file, filename: filename).call
    end

    def initialize(file:, filename: nil)
      @file     = file
      @filename = filename || "unknown.csv"
    end

    def call
      @import = SalesLedger::SalesImport.create!(
        source_filename: @filename,
        status: "processing",
        imported_at: Time.current
      )

      @rows_count             = 0
      @created_products_count = 0
      @created_entries_count  = 0
      @skipped_count          = 0
      @failed_rows            = []

      process_csv

      @import.update!(
        status: "completed",
        rows_count: @rows_count,
        created_products_count: @created_products_count,
        created_entries_count: @created_entries_count,
        failed_rows_count: @failed_rows.size,
        notes: build_notes
      )

      Result.new(success?: true, record: @import, errors: [])
    rescue StandardError => e
      @import&.update!(status: "failed", notes: e.message)
      Rails.logger.error("SalesLedger::ImportCsv failed: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
      Result.new(success?: false, record: @import, errors: [e.message])
    end

    private

    def process_csv
      content = @file.respond_to?(:read) ? @file.read : File.read(@file)
      csv = CSV.parse(content, headers: true, header_converters: :downcase, strip: true)

      # Validate required headers before processing any row
      missing = REQUIRED_COLUMNS - csv.headers.compact
      raise "Faltan columnas requeridas: #{missing.join(', ')}" if missing.any?

      csv.each_with_index do |row, index|
        @rows_count += 1
        process_row(row, index + 2) # +2: line 1 is header, rows are 1-indexed
      rescue StandardError => e
        @failed_rows << "Fila #{index + 2}: #{e.message}"
      end
    end

    def process_row(row, _line)
      data        = parse_and_normalize_row(row)
      fingerprint = compute_fingerprint(data)

      # Skip silently if this exact row was already imported (idempotency)
      if SalesLedger::Entry.exists?(entry_fingerprint: fingerprint)
        @skipped_count += 1
        return
      end

      # Wrap product lookup/creation + entry creation in a single transaction
      ActiveRecord::Base.transaction do
        product, created = find_or_create_product(data)
        @created_products_count += 1 if created

        SalesLedger::Entry.create!(
          sales_import:          @import,
          sale_date:             data[:sale_date],
          ticket_number:         data[:ticket_number],
          oem_code:              data[:oem_code],
          product_name_snapshot: data[:product_name],
          quantity:              data[:quantity],
          unit_price:            data[:unit_price],
          total_amount:          data[:quantity] * data[:unit_price],
          product:               product,
          entry_fingerprint:     fingerprint,
          raw_row_data:          row.to_h
        )

        @created_entries_count += 1
      end
    end

    # Parsea, normaliza y valida una fila del CSV.
    # Raises StandardError con mensaje claro si la fila es inválida.
    def parse_and_normalize_row(row)
      REQUIRED_COLUMNS.each do |col|
        raise "falta valor para '#{col}'" if row[col].blank?
      end

      # Normalización de strings
      raw_oem_code      = row["oem_code"].strip.upcase
      oem_parsed        = parse_oem_code(raw_oem_code)
      raw_ticket_number = row["ticket_number"].strip
      raw_product_name  = row["product_name"].strip
      raw_sale_date     = row["sale_date"].strip
      raw_quantity      = row["quantity"].strip
      raw_unit_price    = row["unit_price"].strip.gsub(/[$,]/, "")

      # Conversiones y validaciones
      sale_date = begin
        Date.parse(raw_sale_date)
      rescue Date::Error
        raise "fecha inválida '#{raw_sale_date}' (usar formato YYYY-MM-DD)"
      end

      quantity = begin
        Integer(raw_quantity)
      rescue ArgumentError
        raise "cantidad inválida '#{raw_quantity}' (debe ser un entero)"
      end
      raise "la cantidad debe ser mayor a 0" unless quantity > 0

      unit_price = begin
        BigDecimal(raw_unit_price)
      rescue ArgumentError
        raise "precio inválido '#{raw_unit_price}'"
      end
      raise "el precio debe ser mayor a 0" unless unit_price > 0

      {
        sale_date:      sale_date,
        ticket_number:  raw_ticket_number,
        oem_code:       raw_oem_code,            # original del CSV — guardado en Entry para trazabilidad
        normalized_sku: oem_parsed[:sku],        # código OEM base sin sufijo — usado en Product.sku
        product_type:   oem_parsed[:product_type],
        product_name:   raw_product_name,
        quantity:       quantity,
        unit_price:     unit_price
      }
    end

    # Dado el código OEM raw (ya stripped y upcased), extrae el SKU base y el product_type.
    #
    # Regla de negocio:
    #   - termina en "-IMP" o "-IM" → product_type "aftermarket", sku sin el sufijo
    #   - cualquier otro caso       → product_type "oem", sku intacto
    #
    # Ejemplos:
    #   "12345"     → { sku: "12345",  product_type: "oem" }
    #   "12345-IM"  → { sku: "12345",  product_type: "aftermarket" }
    #   "12345-IMP" → { sku: "12345",  product_type: "aftermarket" }
    def parse_oem_code(raw_code)
      if raw_code.end_with?("-IMP")
        { sku: raw_code.delete_suffix("-IMP"), product_type: "aftermarket" }
      elsif raw_code.end_with?("-IM")
        { sku: raw_code.delete_suffix("-IM"), product_type: "aftermarket" }
      else
        { sku: raw_code, product_type: "oem" }
      end
    end

    # Busca por sku normalizado + product_type inferido.
    # Si hay múltiples variantes del mismo tipo (distintos brands/origins),
    # toma la primera — comportamiento aceptable para MVP.
    # Si no existe ninguna, crea un producto mínimo sin brand/origin/category.
    def find_or_create_product(data)
      product = Product.find_by(sku: data[:normalized_sku], product_type: data[:product_type])
      return [product, false] if product

      product = Product.create!(
        sku:          data[:normalized_sku],
        name:         data[:product_name],
        product_type: data[:product_type],
        price_unit:   data[:unit_price],
        active:       true
        # brand, origin, category quedan nil intencionalmente
      )

      [product, true]
    end

    # Fingerprint determinístico por fila usando los campos clave.
    # Garantiza idempotencia: reimportar el mismo CSV no duplica entradas.
    def compute_fingerprint(data)
      raw = "#{data[:sale_date]}|#{data[:ticket_number]}|#{data[:oem_code]}|#{data[:quantity]}|#{data[:unit_price]}"
      Digest::SHA256.hexdigest(raw)
    end

    def build_notes
      parts = []
      parts << "#{@skipped_count} fila(s) omitida(s) por duplicado." if @skipped_count > 0
      parts.concat(@failed_rows) if @failed_rows.any?
      parts.join("\n").presence
    end
  end
end
