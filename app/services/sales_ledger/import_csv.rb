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
  #
  # FORMATO ESPERADO DEL CSV
  # Columnas requeridas (en cualquier orden):
  #   ticket_number, oem_code, product_name, quantity, unit_price,
  #   ticket_total_amount, payment_method, seller_name, sale_date
  #
  # Formato de campos monetarios (unit_price, ticket_total_amount):
  #   - Separador decimal: punto (.)
  #   - Separador de miles: coma (,) — opcional, se elimina
  #   - Símbolo $  — opcional, se elimina
  #   - Válido:   1500  |  1500.50  |  1,500.50  |  $1500.50
  #   - Inválido: 1500,50  |  1.500,50  (formato europeo → falla con mensaje claro)
  #
  # payment_method — valores válidos: cash | bank | mercado_pago
  #   Se normaliza con strip + downcase antes de validar.
  class ImportCsv
    REQUIRED_COLUMNS  = %w[
      ticket_number oem_code product_name quantity unit_price
      ticket_total_amount payment_method seller_name sale_date
    ].freeze

    VALID_PAYMENT_METHODS = SalesLedger::Entry::PAYMENT_METHODS

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

      # Pasada 1: parsear todas las filas (acumular errores por fila inválida)
      parsed_pairs = []   # array de [data_hash, raw_csv_row]
      csv.each_with_index do |row, index|
        @rows_count += 1
        data = parse_and_normalize_row(row)
        parsed_pairs << [data, row]
      rescue StandardError => e
        @failed_rows << "Fila #{index + 2}: #{e.message}"
      end

      # Pasada 2: validar consistencia por ticket + anotar ticket_amount_mismatch
      valid_pairs = validate_and_annotate_tickets(parsed_pairs)

      # Pasada 3: persistir filas válidas
      valid_pairs.each do |data, raw_row|
        persist_row(data, raw_row)
      rescue StandardError => e
        @failed_rows << "Ticket #{data[:ticket_number]}: #{e.message}"
      end
    end

    # Parsea, normaliza y valida una fila del CSV.
    # Raises StandardError con mensaje claro si la fila es inválida.
    def parse_and_normalize_row(row)
      REQUIRED_COLUMNS.each do |col|
        raise "falta valor para '#{col}'" if row[col].blank?
      end

      # Normalización de strings
      raw_oem_code        = row["oem_code"].strip.upcase
      oem_parsed          = parse_oem_code(raw_oem_code)
      raw_ticket_number   = row["ticket_number"].strip
      raw_product_name    = row["product_name"].strip
      raw_sale_date       = row["sale_date"].strip
      raw_quantity        = row["quantity"].strip
      raw_unit_price      = row["unit_price"].strip.gsub(/[$,]/, "")
      raw_ticket_total    = row["ticket_total_amount"].strip.gsub(/[$,]/, "")
      raw_payment_method  = row["payment_method"].strip.downcase
      raw_seller_name     = row["seller_name"].strip

      # Conversiones y validaciones
      sale_date = parse_sale_date(raw_sale_date)

      quantity = begin
        Integer(raw_quantity)
      rescue ArgumentError
        raise "cantidad inválida '#{raw_quantity}' (debe ser un entero)"
      end
      raise "la cantidad debe ser mayor a 0" unless quantity > 0

      unit_price = begin
        BigDecimal(raw_unit_price)
      rescue ArgumentError, TypeError
        raise "precio inválido '#{row["unit_price"].strip}' — usar punto como separador decimal"
      end
      raise "el precio debe ser mayor a 0" unless unit_price > 0

      ticket_total_amount = begin
        BigDecimal(raw_ticket_total)
      rescue ArgumentError, TypeError
        raise "ticket_total_amount inválido '#{row["ticket_total_amount"].strip}' — usar punto como separador decimal"
      end
      raise "ticket_total_amount debe ser mayor a 0" unless ticket_total_amount > 0

      unless VALID_PAYMENT_METHODS.include?(raw_payment_method)
        raise "payment_method inválido '#{raw_payment_method}' (válidos: #{VALID_PAYMENT_METHODS.join(', ')})"
      end

      raise "seller_name no puede estar vacío" if raw_seller_name.blank?

      {
        sale_date:           sale_date,
        ticket_number:       raw_ticket_number,
        oem_code:            raw_oem_code,            # original del CSV — guardado en Entry para trazabilidad
        normalized_sku:      oem_parsed[:sku],        # código OEM base sin sufijo — usado en Product.sku
        product_type:        oem_parsed[:product_type],
        product_name:        raw_product_name,
        quantity:            quantity,
        unit_price:          unit_price,
        ticket_total_amount: ticket_total_amount,
        payment_method:      raw_payment_method,
        seller_name:         raw_seller_name
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

    # Agrupa parsed_pairs por ticket_number y para cada ticket:
    #   - Valida que payment_method, seller_name, sale_date y ticket_total_amount
    #     sean idénticos en todas las filas → si no, rechaza el ticket completo.
    #   - Calcula ticket_amount_mismatch: true si el ticket_total_amount declarado
    #     no coincide con la suma de (quantity * unit_price) de las filas del ticket.
    #
    # Devuelve solo las [data, raw_row] de tickets que pasaron la validación de consistencia.
    def validate_and_annotate_tickets(parsed_pairs)
      valid_pairs = []

      parsed_pairs.group_by { |data, _| data[:ticket_number] }.each do |ticket_number, ticket_pairs|
        ticket_rows = ticket_pairs.map(&:first)

        errors = check_ticket_field_consistency(
          ticket_number, ticket_rows,
          :payment_method, :seller_name, :sale_date, :ticket_total_amount
        )

        if errors.any?
          # One failed_rows entry per rejected row so failed_rows_count reflects actual row count
          error_summary = errors.join("; ")
          ticket_pairs.each { @failed_rows << error_summary }
          next
        end

        # ticket_total_amount es consistente entre filas — calcular mismatch
        declared   = ticket_rows.first[:ticket_total_amount]
        calculated = ticket_rows.sum { |r| r[:quantity] * r[:unit_price] }
        mismatch   = (declared - calculated).abs > BigDecimal("0.01")

        ticket_pairs.each do |data, raw_row|
          valid_pairs << [data.merge(ticket_amount_mismatch: mismatch), raw_row]
        end
      end

      valid_pairs
    end

    # Verifica que los campos dados sean idénticos en todas las filas del ticket.
    # Devuelve un array de mensajes de error (vacío si no hay inconsistencias).
    def check_ticket_field_consistency(ticket_number, ticket_rows, *fields)
      fields.filter_map do |field|
        values = ticket_rows.map { |r| r[field] }.uniq
        next if values.size == 1

        "Ticket #{ticket_number}: valor inconsistente en '#{field}' entre filas (#{values.join(' / ')})"
      end
    end

    # Parsea una fecha de venta aceptando los formatos que Google Sheets exporta habitualmente.
    #
    # Formatos aceptados:
    #   YYYY-MM-DD  →  "2026-03-28"
    #   M/D/YYYY    →  "3/28/2026"
    #   M/D/YY      →  "3/28/26"  (00-68 → 2000-2068, 69-99 → 1969-1999)
    #
    # Usamos regex para validar el formato EXACTO antes de llamar a strptime, porque
    # Ruby's strptime ignora caracteres sobrantes al final del string.
    # M/D/YY se maneja manualmente porque %y en strptime no aplica el offset de siglo.
    STRICT_DATE_FORMATS = [
      [/\A\d{4}-\d{1,2}-\d{1,2}\z/,  "%Y-%m-%d"],
      [/\A\d{1,2}\/\d{1,2}\/\d{4}\z/, "%m/%d/%Y"]
    ].freeze

    def parse_sale_date(raw)
      STRICT_DATE_FORMATS.each do |pattern, fmt|
        next unless raw.match?(pattern)
        return Date.strptime(raw, fmt)
      rescue Date::Error
        next
      end

      # M/D/YY: año de 2 dígitos — strptime no aplica el offset de siglo, manejamos manual
      if (m = raw.match(/\A(\d{1,2})\/(\d{1,2})\/(\d{2})\z/))
        yy   = m[3].to_i
        year = yy < 69 ? 2000 + yy : 1900 + yy
        begin
          return Date.new(year, m[1].to_i, m[2].to_i)
        rescue ArgumentError
          # mes o día inválido — cae al raise de abajo
        end
      end

      raise "fecha inválida '#{raw}' (formatos aceptados: YYYY-MM-DD, M/D/YYYY, M/D/YY)"
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

    # Verifica el fingerprint de idempotencia y persiste la entrada.
    # raw_row es el objeto CSV::Row original (strings puras, jsonb-safe).
    def persist_row(data, raw_row)
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
          sales_import:           @import,
          sale_date:              data[:sale_date],
          ticket_number:          data[:ticket_number],
          oem_code:               data[:oem_code],
          product_name_snapshot:  data[:product_name],
          quantity:               data[:quantity],
          unit_price:             data[:unit_price],
          total_amount:           data[:quantity] * data[:unit_price],
          ticket_total_amount:    data[:ticket_total_amount],
          payment_method:         data[:payment_method],
          seller_name:            data[:seller_name],
          ticket_amount_mismatch: data[:ticket_amount_mismatch],
          product:                product,
          entry_fingerprint:      fingerprint,
          raw_row_data:           raw_row.to_h   # strings puras del CSV — jsonb-safe
        )

        @created_entries_count += 1
      end
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
