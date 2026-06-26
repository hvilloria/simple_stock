# frozen_string_literal: true

# Importación de ventas históricas desde sales_to_import.json.
#
# Corre en PRODUCCIÓN. Diseñado para ejecutarse por etapas, con modos de
# verificación que NO tocan la BD.
#
#   bin/rails import_sales:verify_sellers   # solo chequea vendedores (no escribe)
#   bin/rails import_sales:check            # pre-flight completo (no escribe)
#   DRY_RUN=1 bin/rails import_sales:run    # ejecuta todo y hace ROLLBACK (ensayo)
#   bin/rails import_sales:run              # importa de verdad (transaccional)
#
# Archivo por defecto: <rails_root>/sales_to_import.json (override con FILE=...)
#
# Decisiones aplicadas (ver docs/decisiones/ y memoria del proyecto):
#   1. Vendedor: User.find_by(name:); vendedor del ticket = primer seller_name
#      no vacío entre sus filas. Aborta si algún nombre no existe.
#   2. Pagos: cada orden registra Payment + PaymentAllocation por su total →
#      queda confirmed/saldada. Mapeo de método: cash→cash, mercado_pago→
#      mercado_pago, bank→bank_card. Método del ticket = el de la primera fila.
#   3. Total: suma de renglones Σ(qty×unit_price) (lo hace Sales::CreateOrder);
#      se ignora ticket_total_amount. El pago es por ese mismo monto.
#
# Otros: source=from_paper (no valida stock), paper_number=ticket_number,
#   customer=Customer.mostrador, fecha del ticket = la de la primera fila,
#   idempotente (saltea ticket cuyo paper_number ya existe como Order).

namespace :import_sales do
  DEFAULT_FILE  = "sales_to_import.json"
  PAYMENT_MAP   = { "cash" => "cash", "mercado_pago" => "mercado_pago", "bank" => "bank_card" }.freeze
  ORDER_TYPE    = "immediate"
  ORDER_SOURCE  = "from_paper"

  # ---------- helpers ----------

  def load_rows
    path = ENV["FILE"].presence || Rails.root.join(DEFAULT_FILE).to_s
    abort "✗ No existe el archivo: #{path}" unless File.exist?(path)
    rows = JSON.parse(File.read(path))
    puts "Archivo: #{path}"
    puts "Filas: #{rows.size}  |  Tickets: #{rows.map { |r| r['ticket_number'] }.uniq.size}"
    rows
  end

  # Agrupa filas en tickets, resolviendo los valores efectivos de cada uno.
  # Devuelve array de hashes: { number, seller, payment_raw, sale_date, items: [...] }
  def build_tickets(rows)
    rows.group_by { |r| r["ticket_number"] }.map do |number, ticket_rows|
      first = ticket_rows.first
      {
        number:      number,
        seller:      ticket_rows.map { |r| r["seller_name"].to_s.strip }.find(&:present?),
        payment_raw: first["payment_method"].to_s.strip,
        sale_date:   first["sale_date"],
        items: ticket_rows.map do |r|
          {
            oem_code:   r["oem_code"].to_s.strip,
            name:       r["product_name"].to_s.strip,
            quantity:   r["quantity"].to_i,
            unit_price: r["unit_price"].to_f
          }
        end
      }
    end
  end

  # Mapa oem_code => { name:, price: } usando la PRIMERA aparición en el archivo.
  # Registra conflictos (mismo código con más de un nombre).
  def build_product_specs(rows)
    specs     = {}
    conflicts = Hash.new { |h, k| h[k] = [] }
    rows.each do |r|
      code  = r["oem_code"].to_s.strip
      name  = r["product_name"].to_s.strip
      price = r["unit_price"].to_f
      if specs.key?(code)
        conflicts[code] << name unless specs[code][:name] == name || conflicts[code].include?(name)
      else
        specs[code] = { name: name, price: price }
      end
    end
    [ specs, conflicts ]
  end

  # ---------- 1) solo vendedores ----------

  desc "Verifica que los vendedores del archivo existan en la BD (no escribe)"
  task verify_sellers: :environment do
    tickets = build_tickets(load_rows)
    names   = tickets.map { |t| t[:seller] }.compact.uniq.sort
    unresolved = tickets.select { |t| t[:seller].nil? }.map { |t| t[:number] }

    puts
    puts "== Vendedores efectivos (User.find_by(name:)) =="
    missing = []
    names.each do |name|
      user = User.find_by(name: name)
      count = tickets.count { |t| t[:seller] == name }
      if user
        puts "  ✓ #{name.ljust(12)} -> User##{user.id} email=#{user.email} role=#{user.role} (#{count} tickets)"
      else
        puts "  ✗ #{name.ljust(12)} -> NO ENCONTRADO (#{count} tickets)"
        missing << name
      end
    end

    puts
    puts(unresolved.any? ? "⚠ Tickets sin vendedor (#{unresolved.size}): #{unresolved.inspect}" : "✓ Todos los tickets tienen vendedor.")
    puts
    if missing.empty? && unresolved.empty?
      puts "✅ OK: #{names.size} vendedores existen y todos los tickets resuelven."
    else
      abort "❌ Faltan: vendedores=#{missing.inspect}, tickets sin vendedor=#{unresolved.size}."
    end
  end

  # ---------- 2) pre-flight completo (read-only) ----------

  desc "Pre-flight completo: valida vendedores, métodos, productos y consistencia (no escribe)"
  task check: :environment do
    rows    = load_rows
    tickets = build_tickets(rows)
    errors  = []

    # --- vendedores ---
    seller_names = tickets.map { |t| t[:seller] }.compact.uniq
    missing_sellers = seller_names.reject { |n| User.exists?(name: n) }
    errors << "Vendedores no encontrados: #{missing_sellers.inspect}" if missing_sellers.any?
    no_seller = tickets.select { |t| t[:seller].nil? }.map { |t| t[:number] }
    errors << "Tickets sin vendedor: #{no_seller.inspect}" if no_seller.any?

    # --- métodos de pago ---
    raw_methods   = tickets.map { |t| t[:payment_raw] }.uniq
    unmappable    = raw_methods.reject { |m| PAYMENT_MAP.key?(m) }
    errors << "payment_method sin mapeo: #{unmappable.inspect}" if unmappable.any?
    mapped_targets = PAYMENT_MAP.values_at(*(raw_methods & PAYMENT_MAP.keys)).uniq
    bad_targets    = mapped_targets.reject { |m| Payment::PAYMENT_METHODS.include?(m) }
    errors << "métodos mapeados que no están en Payment::PAYMENT_METHODS: #{bad_targets.inspect}" if bad_targets.any?

    # --- consistencia de ítems ---
    bad_qty   = rows.count { |r| r["quantity"].to_i <= 0 }
    bad_price = rows.count { |r| r["unit_price"].to_f <= 0 }
    errors << "Filas con quantity<=0: #{bad_qty}"   if bad_qty.positive?
    errors << "Filas con unit_price<=0: #{bad_price}" if bad_price.positive?

    # --- productos ---
    specs, conflicts = build_product_specs(rows)
    existing = Product.where(sku: specs.keys).distinct.pluck(:sku)
    to_create = specs.keys - existing

    # --- idempotencia ---
    already = Order.where(paper_number: tickets.map { |t| t[:number] }).pluck(:paper_number).uniq

    puts
    puts "== Resumen =="
    puts "  Tickets (órdenes a crear)        : #{tickets.size}"
    puts "  Ya importados (paper_number existe): #{already.size}#{already.any? ? " -> se saltearán" : ""}"
    puts "  Productos únicos (oem_code)      : #{specs.size}"
    puts "    - ya existen en BD             : #{existing.size}"
    puts "    - se crearán                   : #{to_create.size}"
    puts "  Métodos de pago en uso           : #{raw_methods.sort.inspect} -> #{raw_methods.map { |m| PAYMENT_MAP[m] }.compact.uniq.inspect}"
    puts "  Vendedores                       : #{seller_names.sort.inspect}"
    if conflicts.any?
      puts
      puts "  ⚠ Códigos con más de un nombre (se usará el de la 1ra aparición):"
      conflicts.each { |code, others| puts "      #{code}: queda \"#{specs[code][:name]}\"  (descarta: #{others.inspect})" }
    end

    puts
    if errors.empty?
      puts "✅ Pre-flight OK. Listo para correr DRY_RUN=1 bin/rails import_sales:run"
    else
      puts "❌ Pre-flight con problemas:"
      errors.each { |e| puts "   - #{e}" }
      abort "Resolver antes de importar."
    end
  end

  # ---------- 3) import real (transaccional, con DRY_RUN) ----------

  desc "Importa las ventas (productos, órdenes, ítems y pagos). DRY_RUN=1 para ensayar sin guardar."
  task run: :environment do
    dry = ENV["DRY_RUN"].present?
    rows    = load_rows
    tickets = build_tickets(rows)
    specs, conflicts = build_product_specs(rows)

    # Validaciones bloqueantes mínimas (el detalle está en :check)
    seller_names = tickets.map { |t| t[:seller] }.compact.uniq
    users = seller_names.index_with { |n| User.find_by(name: n) }
    if (missing = users.select { |_, u| u.nil? }.keys).any?
      abort "❌ Vendedores no encontrados: #{missing.inspect}. Corré import_sales:verify_sellers."
    end
    if (no_seller = tickets.select { |t| t[:seller].nil? }).any?
      abort "❌ Tickets sin vendedor: #{no_seller.map { |t| t[:number] }.inspect}."
    end
    if (bad = tickets.map { |t| t[:payment_raw] }.uniq.reject { |m| PAYMENT_MAP.key?(m) }).any?
      abort "❌ payment_method sin mapeo: #{bad.inspect}."
    end

    stats = Hash.new(0)
    puts
    puts(dry ? ">>> DRY RUN — se hará ROLLBACK al final, nada se persiste." : ">>> IMPORT REAL")
    puts "Conflictos de nombre (se usa el 1ro): #{conflicts.keys.inspect}" if conflicts.any?

    begin
      ActiveRecord::Base.transaction do
        mostrador = Customer.mostrador

        # --- productos ---
        product_by_code = {}
        specs.each do |code, spec|
          product = Product.find_by(sku: code)
          if product
            stats[:products_existing] += 1
          else
            product = Product.create!(sku: code, name: spec[:name], price_unit: spec[:price])
            stats[:products_created] += 1
          end
          product_by_code[code] = product
        end

        # --- órdenes + ítems + pagos ---
        tickets.each do |t|
          if Order.exists?(paper_number: t[:number])
            stats[:tickets_skipped] += 1
            next
          end

          items = t[:items].map do |it|
            { product_id: product_by_code.fetch(it[:oem_code]).id,
              quantity:   it[:quantity],
              unit_price: it[:unit_price] }
          end

          result = Sales::CreateOrder.call(
            customer:     mostrador,
            items:        items,
            order_type:   ORDER_TYPE,
            paper_number: t[:number],
            user:         users.fetch(t[:seller]),
            source:       ORDER_SOURCE,
            sale_date:    t[:sale_date]
          )
          raise "Ticket #{t[:number]}: #{result.errors.join(', ')}" if result.failure?

          order   = result.record
          method  = PAYMENT_MAP.fetch(t[:payment_raw])
          payment = Payment.create!(
            customer:       mostrador,
            amount:         order.total_amount,
            payment_method: method,
            payment_date:   order.sale_date
          )
          PaymentAllocation.create!(payment: payment, order: order, amount: order.total_amount)
          order.refresh_status_from_balance!

          stats[:orders_created]   += 1
          stats[:payments_created] += 1
        end

        puts
        puts "== Resultado =="
        puts "  Productos creados   : #{stats[:products_created]}"
        puts "  Productos existentes: #{stats[:products_existing]}"
        puts "  Órdenes creadas     : #{stats[:orders_created]}"
        puts "  Pagos creados       : #{stats[:payments_created]}"
        puts "  Tickets salteados   : #{stats[:tickets_skipped]} (ya existían)"

        if dry
          puts
          puts ">>> DRY RUN: rollback."
          raise ActiveRecord::Rollback
        end
      end
    rescue ActiveRecord::Rollback
      # esperado en dry-run
    end

    puts
    puts(dry ? "✅ DRY RUN completado (nada se guardó)." : "✅ Import completado.")
  end
end
