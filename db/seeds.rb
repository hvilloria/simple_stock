# db/seeds.rb

# Clean only in development
if Rails.env.development?
  puts "🗑️  Limpiando datos existentes..."
  # Sealed cash movements refuse destroy by design; the dev reset skips the guard.
  CashMovement.delete_all
  DailyClosing.delete_all
  [ PaymentAllocation, Payment, OrderItem, Order, InvoiceItem, AppliedCredit, CreditNote,
    Invoice, StockMovement, Customer, Supplier, StockLocation, User ].each(&:destroy_all)
  # Product is soft-deleted (acts_as_paranoid), so destroy_all would leave ghost
  # rows that pile up on every re-seed. Hard-delete all rows (incl. already
  # soft-deleted ones) after their children are gone, so the dev reset is clean.
  Product.with_deleted.delete_all
  puts "✅ Base de datos limpiada"
end

# ============================================
# 0. USERS
# ============================================
puts "\n🔐 Creando usuarios iniciales..."
if User.count.zero?
  admin = User.create!(
    email: "administracion@gentedelsol.com",
    password: "admin",
    password_confirmation: "admin",
    name: "Administrador",
    role: "admin"
  )

  vendedor = User.create!(
    email: "vendedor@gentedelsol.com",
    password: "vendedor",
    password_confirmation: "vendedor",
    name: "Vendedor",
    role: "vendedor"
  )

  caja = User.create!(
    email: "caja@gentedelsol.com",
    password: "caja",
    password_confirmation: "caja",
    name: "Caja",
    role: "caja"
  )

  puts "✅ Usuarios creados:"
  puts "   #{admin.role}: #{admin.email} / admin"
  puts "   #{vendedor.role}: #{vendedor.email} / vendedor"
  puts "   #{caja.role}: #{caja.email} / caja"
  puts "   ⚠️  CAMBIAR PASSWORDS EN PRODUCCIÓN"
else
  puts "✅ Usuarios ya existen, saltando creación"
end

# User associated with the seed orders (feat_14: Order#user is mandatory)
seller_user = User.find_by(role: "vendedor") || User.first!
cashier_user = User.find_by(role: "caja") || User.first!

# ============================================
# 1. STOCK LOCATION
# ============================================
puts "\n📍 Creando ubicación de stock..."
stock_location = StockLocation.create!(
  name: "Depósito Principal",
  code: "DEP-01",
  address: "Av. Warnes 620, CABA, Buenos Aires"
)

# ============================================
# 2. SUPPLIERS (5)
# ============================================
puts "\n🏭 Creando proveedores..."
supplier_japan = FactoryBot.create(:supplier, :japan)
supplier_usa = FactoryBot.create(:supplier, :usa)
supplier_germany = FactoryBot.create(:supplier, :germany)
supplier_taiwan = FactoryBot.create(:supplier, :taiwan)
supplier_brazil = FactoryBot.create(:supplier, :brazil)

suppliers = [ supplier_japan, supplier_usa, supplier_germany, supplier_taiwan, supplier_brazil ]
puts "✅ #{suppliers.count} proveedores creados"

# ============================================
# 3. CUSTOMERS
# ============================================
puts "\n👥 Creando clientes..."

# Cliente Mostrador
mostrador = Customer.find_or_create_by!(name: "Cliente Mostrador") do |c|
  c.customer_type = "retail"
  c.has_credit_account = false
end

# Workshops with realistic Argentine names
talleres = [
  FactoryBot.create(:customer, :workshop,
    name: "Taller Mecánico El Rayo",
    document: "30-71234567-8",
    phone: "11-4567-8901"
  ),
  FactoryBot.create(:customer, :workshop,
    name: "Mecánica Los Pibes",
    document: "30-71234568-9",
    phone: "11-4567-8902"
  ),
  FactoryBot.create(:customer, :workshop,
    name: "Taller Don Carlos",
    document: "30-71234569-0",
    phone: "11-4567-8903"
  ),
  FactoryBot.create(:customer, :workshop,
    name: "Auto Service La Plata",
    document: "30-71234570-1",
    phone: "221-456-7890"
  )
]

# Individual customer
particular = FactoryBot.create(:customer, :with_credit,
  name: "Juan Pérez",
  document: "20-35678901-2",
  phone: "11-5678-9012",
  customer_type: "mechanic"
)

clientes_con_credito = talleres + [ particular ]
puts "✅ Cliente Mostrador + #{clientes_con_credito.count} clientes con cuenta corriente"

# ============================================
# 4. PRODUCTS (200 varied Honda products)
# ============================================
puts "\n🔧 Creando 200 productos Honda..."

# Realistic names by category
PRODUCTOS_REALES = {
  frenos: [
    "Pastillas de Freno Delanteras", "Pastillas de Freno Traseras",
    "Discos de Freno Delanteros", "Discos de Freno Traseros",
    "Tambores de Freno", "Zapatas de Freno Traseras",
    "Cilindro Maestro de Freno", "Bomba de Freno ABS",
    "Mangueras de Freno", "Líquido de Frenos DOT 4",
    "Kit de Reparación de Pinza", "Sensor de Desgaste de Pastillas"
  ],
  motor: [
    "Filtro de Aceite", "Filtro de Aire", "Filtro de Combustible",
    "Bujías NGK", "Cables de Bujía", "Bobina de Encendido",
    "Junta de Culata", "Junta de Carter", "Correa de Distribución",
    "Tensor de Correa de Distribución", "Bomba de Agua", "Termostato",
    "Radiador", "Ventilador de Radiador", "Tapa de Radiador",
    "Sensor de Temperatura", "Sensor de Oxígeno O2", "Sensor MAP",
    "Múltiple de Admisión", "Múltiple de Escape", "Catalizador",
    "Silenciador", "Tubo de Escape", "Tapa de Válvulas",
    "Bomba de Aceite", "Válvula PCV", "Válvula EGR"
  ],
  suspension: [
    "Amortiguador Delantero Derecho", "Amortiguador Delantero Izquierdo",
    "Amortiguador Trasero Derecho", "Amortiguador Trasero Izquierdo",
    "Espiral Delantero", "Espiral Trasero",
    "Barra Estabilizadora Delantera", "Barra Estabilizadora Trasera",
    "Goma de Barra Estabilizadora", "Brazo Inferior Derecho",
    "Brazo Inferior Izquierdo", "Rótula Superior", "Rótula Inferior",
    "Bujes de Brazo", "Cazoleta de Amortiguador"
  ],
  transmision: [
    "Kit de Embrague Completo", "Disco de Embrague",
    "Plato de Embrague", "Collarin de Embrague",
    "Cable de Embrague", "Aceite de Transmisión ATF",
    "Aceite de Caja Manual", "Semieje Derecho CVT",
    "Semieje Izquierdo CVT", "Crucetas de Cardan",
    "Guardapolvos de Transmisión", "Filtro de Transmisión Automática"
  ],
  electrico: [
    "Batería 12V 45Ah", "Batería 12V 60Ah",
    "Alternador 90A", "Motor de Arranque",
    "Regulador de Voltaje", "Cables de Batería",
    "Caja de Fusibles", "Relé Principal",
    "Switch de Encendido", "Faros Delanteros LED",
    "Luces Traseras", "Luces de Freno",
    "Sensor MAF", "Sensor de Cigüeñal",
    "ECU Computadora", "Arnés Eléctrico Principal"
  ],
  carroceria: [
    "Paragolpes Delantero", "Paragolpes Trasero",
    "Guardabarros Delantero Derecho", "Guardabarros Delantero Izquierdo",
    "Capot", "Portón Trasero", "Puerta Delantera Derecha",
    "Puerta Delantera Izquierda", "Espejo Retrovisor Derecho",
    "Espejo Retrovisor Izquierdo", "Manija de Puerta",
    "Cerradura de Puerta", "Luneta Trasera"
  ],
  filtros: [
    "Filtro de Aceite OEM", "Filtro de Aire Motor OEM",
    "Filtro de Combustible OEM", "Filtro de Polen/Cabina",
    "Filtro de Transmisión Automática", "Filtro Hidráulico Dirección"
  ],
  lubricantes: [
    "Aceite Motor 0W-20 Sintético", "Aceite Motor 5W-30",
    "Aceite Motor 10W-40", "Aceite Transmisión Manual SAE 75W-90",
    "Aceite Transmisión Automática ATF DW-1", "Aceite Diferencial",
    "Grasa Multiuso Lithium", "Líquido Refrigerante Long Life",
    "Líquido de Dirección Hidráulica", "Líquido Limpiaparabrisas"
  ]
}

productos = []
counter = 1

PRODUCTOS_REALES.each do |categoria, nombres|
  nombres.each do |nombre|
    break if counter > 200

    # Determine type, origin and brand (40% OEM Japan, 20% OEM USA, 40% Aftermarket)
    rand_val = rand(100)

    if rand_val < 40
      # OEM Japan
      trait_origen = :oem_japan
      brand = "Honda"
      cost_usd = rand(20..150).round(2)
      price_multiplier = 1.8
    elsif rand_val < 60
      # OEM USA
      trait_origen = :oem_usa
      brand = "Honda"
      cost_usd = rand(15..120).round(2)
      price_multiplier = 1.6
    else
      # Aftermarket (distribute origins and brands)
      origins_brands = {
        aftermarket_germany: [ "Bosch", "Continental", "Sachs" ],
        aftermarket_korea: [ "Hyundai Mobis", "Mando", "CTR" ],
        aftermarket_brazil: [ "Cofap", "Metal Leve", "TRW" ],
        aftermarket_china: [ "KYB", "Moog", "Febi" ],
        aftermarket_taiwan: [ "TYC", "Depo", "GMB" ],
        aftermarket_india: [ "Valeo", "Mahle", "ZF" ]
      }

      trait_origen = origins_brands.keys.sample
      brand = origins_brands[trait_origen].sample
      cost_usd = rand(10..100).round(2)
      price_multiplier = 1.3
    end

    # Calculate price in ARS
    exchange_rate = rand(1150..1250)
    # Counter prices land between 10.000 and 500.000, mostly round thousands.
    price_ars = (cost_usd * exchange_rate * price_multiplier).clamp(10_000, 500_000)
    price_ars = rand(100) < 70 ? (price_ars / 1_000).round * 1_000 : (price_ars / 100).round * 100

    # Generate a valid physical location: [aisle 1-9][side I/D][position 0-9][level 0-9]
    # 80% of the products have a location, 20% unassigned
    location_code = if rand(100) < 80
      pasillo = rand(1..9)
      lado = [ 'I', 'D' ].sample
      posicion = rand(0..9)
      nivel = rand(0..4)  # Levels 0-4 (5 levels maximum)
      "#{pasillo}#{lado}#{posicion}#{nivel}"
    else
      nil  # No location assigned
    end

    producto = FactoryBot.create(
      :product,
      categoria,
      trait_origen,
      :honda_part,
      name: "#{nombre} Honda",
      sku: "HDC#{counter.to_s.rjust(3, '0')}",
      brand: brand,
      cost_unit: cost_usd,
      cost_currency: "USD",
      price_unit: price_ars,
      current_stock: 0,
      location_code: location_code
    )

    productos << producto
    counter += 1
  end
end

puts "✅ #{productos.count} productos creados"
puts "   - OEM Japan: #{productos.count { |p| p.origin == 'japan' && p.oem? }}"
puts "   - OEM USA: #{productos.count { |p| p.origin == 'usa' && p.oem? }}"
puts "   - Aftermarket: #{productos.count { |p| p.aftermarket? }}"

# ============================================
# 5. PURCHASES (20 purchases in the last 30 days)
# ============================================
puts "\n📦 Creando compras..."

compras_exitosas = 0
20.times do |i|
  supplier = suppliers.sample
  fecha = rand(30).days.ago.to_date

  # 5-15 random products
  productos_compra = productos.sample(rand(5..15))

  items = productos_compra.map do |producto|
    {
      product_id: producto.id,
      quantity: rand(10..100),
      unit_cost: rand(5.0..150.0).round(2)
    }
  end

  result = Purchasing::CreatePurchase.call(
    supplier: supplier,
    items: items,
    currency: "USD",
    exchange_rate: rand(1150.0..1250.0).round(2),
    purchase_date: fecha,
    notes: "Compra importación - #{supplier.name}"
  )

  if result.success?
    result.record.update_column(:created_at, fecha.to_time + rand(8..18).hours)
    compras_exitosas += 1
    print "."
  else
    puts "\n❌ Error en compra: #{result.errors.join(', ')}"
  end
end

puts "\n✅ #{compras_exitosas}/20 compras creadas"

# ============================================
# 6. SALES (50 sales in the last 7 days)
# ============================================
puts "\n💰 Creando ventas (esto puede tardar un poco)..."

ventas_exitosas = 0
sale_counter = 1

# Counter-sized amounts: a multiple of 100, usually a round thousand.
monto_redondo = lambda do |min, max|
  monto = rand(min..max)
  rand(100) < 70 ? (monto / 1_000.0).round * 1_000 : (monto / 100.0).round * 100
end

# A sale note's total is picked first (80% under 100.000, the rest up to
# 500.000) and then split across single-unit lines.
items_para_nota = lambda do
  chica = rand(100) < 80
  total = chica ? monto_redondo.(10_000, 99_000) : monto_redondo.(100_000, 500_000)
  pesos = Array.new(chica ? rand(1..2) : rand(1..4)) { rand(1..10) }
  partes = pesos[0...-1].map { |peso| (total * peso / pesos.sum / 100) * 100 }
  partes << total - partes.sum

  productos.sample(partes.size).zip(partes).map do |producto, precio|
    { product_id: producto.id, quantity: 1, unit_price: precio }
  end
end

# 45 counter sales
45.times do
  fecha = rand(7).days.ago + rand(24).hours
  items = items_para_nota.()

  result = Sales::CreateOrder.call(
    customer: mostrador,
    user: seller_user,
    items: items,
    order_type: "immediate",
    paper_number: "T-#{format('%04d', sale_counter)}",
    channel: [ 'counter', 'whatsapp', 'mercadolibre' ].sample,
    source: "from_paper"
  )

  if result.success?
    result.record.update_column(:created_at, fecha)
    ventas_exitosas += 1
    print "."
  end

  sale_counter += 1
end

# 5 credit sales
5.times do
  fecha = rand(7).days.ago + rand(24).hours
  cliente = clientes_con_credito.sample
  items = items_para_nota.()

  result = Sales::CreateOrder.call(
    customer: cliente,
    user: seller_user,
    items: items,
    order_type: "credit",
    paper_number: "T-#{format('%04d', sale_counter)}",
    channel: "counter",
    source: "from_paper"
  )

  if result.success?
    result.record.update_column(:created_at, fecha)
    ventas_exitosas += 1
    print "."
  end

  sale_counter += 1
end

puts "\n✅ #{ventas_exitosas} ventas creadas"

# ============================================
# 6.5 ON-ACCOUNT PAYMENTS (open operations)
# ============================================
puts "\n🗂️  Creando pagos a cuenta..."

contactos_pac = [
  { name: "Ramón Gutiérrez", phone: "11-6123-4501" },
  { name: "Laura Benítez",   phone: "11-6123-4502" },
  { name: "Diego Sosa",      phone: "11-6123-4503" },
  { name: "Marta Quiroga",   phone: "11-6123-4504" },
  { name: "Esteban Ríos",    phone: "11-6123-4505" }
]

pac_creados = 0

crear_pac = lambda do |contacto:, entregados_idx: [], cobrar_fraccion: nil|
  fecha = (1 + rand(10)).days.ago.beginning_of_day + rand(24).hours
  items = items_para_nota.()

  result = Sales::CreateOrder.call(
    customer: mostrador,
    user: seller_user,
    items: items,
    order_type: "on_account",
    paper_number: "T-#{format('%04d', sale_counter)}",
    channel: "counter",
    source: "from_paper",
    contact_name: contacto[:name],
    contact_phone: contacto[:phone],
    delivered_product_ids: entregados_idx.filter_map { |i| items[i]&.dig(:product_id) }
  )
  sale_counter += 1

  unless result.success?
    puts "  ✗ #{contacto[:name]}: #{result.errors.join(', ')}"
    next
  end

  order = result.record
  order.update_column(:created_at, fecha)

  if cobrar_fraccion
    monto = (order.outstanding_balance * cobrar_fraccion).round(2)
    if monto.positive?
      Payments::CollectOnAccount.call(
        order: order,
        discount_percent: 0,
        tenders: [ { payment_method: "cash", amount: monto } ],
        payment_date: fecha.to_date,
        user: cashier_user
      )
    end
  end

  pac_creados += 1
  order.reload
  puts "  ✓ #{contacto[:name]}: saldo $#{order.outstanding_balance.to_i} | " \
       "entrega #{order.delivered_items_count}/#{order.order_items.size}"
end

# Deposit paid, nothing delivered (waiting for the part)
crear_pac.(contacto: contactos_pac[0], entregados_idx: [], cobrar_fraccion: 0.3)
# Partially delivered, with outstanding balance
crear_pac.(contacto: contactos_pac[1], entregados_idx: [ 0, 1 ], cobrar_fraccion: 0.5)
# Fully paid but one item still to be picked up (stays open)
crear_pac.(contacto: contactos_pac[2], entregados_idx: [ 0 ], cobrar_fraccion: 1.0)
# Just created: partial initial delivery, no collections
crear_pac.(contacto: contactos_pac[3], entregados_idx: [ 0 ], cobrar_fraccion: nil)
# Just created: nothing delivered, nothing paid
crear_pac.(contacto: contactos_pac[4], entregados_idx: [], cobrar_fraccion: nil)

puts "✅ #{pac_creados} pagos a cuenta creados (abiertos: #{Order.open_on_account.length})"

# ============================================
# 7. PAYMENTS (2-3 partial payments)
# ============================================
puts "\n💵 Registrando pagos..."

pagos_creados = 0
clientes_con_credito.each do |cliente|
  ordenes = Order.where(customer: cliente, order_type: "credit", status: "pending").to_a
  next if ordenes.empty?

  saldo_total = ordenes.sum(&:outstanding_balance)
  next unless saldo_total > 1000

  metodo = %w[cash bank_transfer bank_card].sample
  monto_total = (saldo_total * rand(0.3..0.7)).round(2)
  fecha_pago = (1 + rand(3)).days.ago.to_date

  restante = monto_total
  allocations = []
  ordenes.each do |orden|
    break if restante <= 0
    saldo_orden = orden.outstanding_balance
    next if saldo_orden <= 0
    aplicar = [ saldo_orden, restante ].min.round(2)
    allocations << { order_id: orden.id, amount: aplicar, payment_method: metodo }
    restante = (restante - aplicar).round(2)
  end

  next if allocations.empty?

  result = Payments::AllocatePayment.call(
    customer: cliente,
    payment_date: fecha_pago,
    allocations: allocations,
    notes: "Pago parcial - #{metodo}",
    user: cashier_user
  )

  if result.success?
    pagos_creados += 1
    puts "  ✓ #{cliente.name}: $#{monto_total.to_i} | Saldo: $#{cliente.reload.current_balance.to_i}"
  else
    puts "  ✗ #{cliente.name}: #{result.errors.join(', ')}"
  end
end

puts "✅ #{pagos_creados} pagos registrados"

# ============================================
# 8. PENDING SIMPLE INVOICES
# ============================================
puts "\n📄 Creando facturas simples pendientes (ARS)..."

inv_seq = 1
inv_ok  = 0

create_inv = ->(supplier, amount, purchase_date, due_date, opts = {}) do
  num = "SF-#{format('%04d', inv_seq)}"
  inv_seq += 1

  result = Invoices::CreateInvoice.call(
    supplier:                          supplier,
    invoice_number:                    num,
    amount:                            amount,
    currency:                          "ARS",
    exchange_rate:                     nil,
    purchase_date:                     purchase_date,
    due_date:                          due_date,
    early_payment_due_date:            opts[:ep_date],
    early_payment_discount_percentage: opts[:ep_pct]
  )

  if result.success?
    inv_ok += 1
  else
    puts "  ✗ #{num}: #{result.errors.join(', ')}"
  end
  result
end

today      = Date.current
monday     = today.beginning_of_week(:monday)
nxt_monday = monday + 7

# ── Case 1: Due this week ──────────────────────────────────────
puts "  → Esta semana (#{monday.strftime('%d/%m')} - #{(monday + 6).strftime('%d/%m')})..."

create_inv.(supplier_japan,    134_862.37, today - 30, monday + 1)
create_inv.(supplier_japan,    195_041.83, today - 25, monday + 3)
create_inv.(supplier_usa,      108_773.14, today - 20, monday + 2)
create_inv.(supplier_usa,      156_308.62, today - 28, monday + 4)
create_inv.(supplier_germany,  247_456.91, today - 22, monday + 1)
create_inv.(supplier_taiwan,    83_219.48, today - 18, monday + 3)
create_inv.(supplier_taiwan,    96_587.06, today - 15, monday + 5)
create_inv.(supplier_brazil,    81_934.72, today - 30, monday + 2)

# ── Case 2: Due next week ────────────────────────────────
puts "  → Semana próxima (#{nxt_monday.strftime('%d/%m')} - #{(nxt_monday + 6).strftime('%d/%m')})..."

create_inv.(supplier_japan,    178_304.56, today - 10, nxt_monday + 1)
create_inv.(supplier_usa,      121_089.23, today - 8,  nxt_monday + 2)
create_inv.(supplier_usa,      287_614.79, today - 12, nxt_monday + 4)
create_inv.(supplier_germany,  147_523.38, today - 5,  nxt_monday + 1)
create_inv.(supplier_germany,  216_047.61, today - 15, nxt_monday + 3)
create_inv.(supplier_taiwan,   110_782.94, today - 7,  nxt_monday + 2)
create_inv.(supplier_brazil,    68_491.17, today - 9,  nxt_monday + 1)
create_inv.(supplier_brazil,   114_236.85, today - 11, nxt_monday + 4)

# ── Case 3: Early-payment discount is due this week (with_discount_to_advance) ──
puts "  → Con descuento anticipado (expira en #{today + 1}..#{today + 3})..."

create_inv.(supplier_japan,    356_128.43, today - 45, today + 30, ep_date: today + 2, ep_pct: 5)
create_inv.(supplier_usa,      237_865.09, today - 40, today + 25, ep_date: today + 1, ep_pct: 7)
create_inv.(supplier_germany,  495_702.36, today - 50, today + 35, ep_date: today + 2, ep_pct: 10)
create_inv.(supplier_taiwan,   158_047.82, today - 38, today + 28, ep_date: today + 1, ep_pct: 8)
create_inv.(supplier_brazil,   149_583.67, today - 42, today + 32, ep_date: today + 3, ep_pct: 6)

# ── Case 4: Additional variety for the index view ──────────────
puts "  → Variedad para el índice (vencidas, este mes, próximo mes)..."

# Overdue
create_inv.(supplier_japan,    95_318.54, today - 60, today - 15)
create_inv.(supplier_usa,      77_642.31, today - 45, today - 7)
create_inv.(supplier_germany,  261_409.78, today - 30, today - 3)

# This month (outside this week and next)
create_inv.(supplier_taiwan,   133_856.29, today - 5,  today + 14)
create_inv.(supplier_brazil,    91_074.53, today - 3,  today + 18)
create_inv.(supplier_japan,    116_493.87, today - 7,  today + 21)

# Next month
create_inv.(supplier_usa,      175_237.46, today - 2,  today + 35)
create_inv.(supplier_germany,  269_815.92, today - 8,  today + 42)

# ── Paid (created and then marked as paid) ─────────────────────
[
  [ supplier_japan,   297_183.64, today - 35 ],
  [ supplier_usa,     148_726.41, today - 28 ],
  [ supplier_germany, 384_059.17, today - 20 ],
  [ supplier_taiwan,  123_892.35, today - 42 ],
  [ supplier_brazil,  163_447.28, today - 15 ]
].each do |sup, amount, paid_date|
  num = "SF-#{format('%04d', inv_seq)}"
  inv_seq += 1

  result = Invoices::CreateInvoice.call(
    supplier:      sup,
    invoice_number: num,
    amount:        amount,
    currency:      "ARS",
    exchange_rate: nil,
    purchase_date: paid_date - 30,
    due_date:      paid_date - 5
  )

  if result.success?
    result.record.update_columns(status: "paid", paid_at: paid_date)
    inv_ok += 1
  end
end

puts "✅ #{inv_ok} facturas simples creadas"
puts "   - Esta semana:               8"
puts "   - Semana próxima:            8"
puts "   - Descuento anticipado:      5"
puts "   - Vencidas/este mes/futuras: 8"
puts "   - Pagadas:                   5"

# ============================================
# 9. CREDIT NOTES
# ============================================
puts "\n📝 Creando notas de crédito..."

cn_seq = 1
cn_ok  = 0

create_cn = ->(supplier, amount, issue_date, opts = {}) do
  num = "NC-#{format('%04d', cn_seq)}"
  cn_seq += 1

  CreditNote.create!(
    supplier:           supplier,
    credit_note_number: num,
    amount:             amount,
    currency:           opts.fetch(:currency, "ARS"),
    exchange_rate:      opts[:exchange_rate],
    issue_date:         issue_date,
    status:             "active",
    notes:              opts[:notes]
  )
  cn_ok += 1
end

# Japan: 2 notes in ARS
create_cn.(supplier_japan,  84_763.29, today - 20, notes: "Devolución mercadería defectuosa - Lote J201")
create_cn.(supplier_japan, 129_408.54, today - 10, notes: "Ajuste de precio sobre factura anterior")

# USA: 1 note in ARS
create_cn.(supplier_usa, 209_317.83, today - 15, notes: "NC por error de facturación en pedido #US-88")

# Germany: 2 notes (1 ARS, 1 USD)
create_cn.(supplier_germany, 174_652.47, today - 8, notes: "Descuento por volumen retroactivo Q4")
create_cn.(supplier_germany,     198.36, today - 5,
  currency: "USD", exchange_rate: 1200.0,
  notes: "Devolución por piezas incorrectas - Ref DEU-44"
)

# Taiwan: 1 small note in ARS
create_cn.(supplier_taiwan, 54_891.62, today - 12, notes: "Faltante en pedido anterior - ajuste")

# Brazil: 1 note in ARS
create_cn.(supplier_brazil, 89_534.18, today - 18, notes: "Mercadería dañada en tránsito - reembolso parcial")

puts "✅ #{cn_ok} notas de crédito creadas"
puts "   - Japan:   2 notas ARS ($84.763,29 + $129.408,54)"
puts "   - USA:     1 nota  ARS ($209.317,83)"
puts "   - Germany: 2 notas (ARS $174.652,47 + USD $198,36)"
puts "   - Taiwan:  1 nota  ARS ($54.891,62)"
puts "   - Brazil:  1 nota  ARS ($89.534,18)"

# ============================================
# 9.5 CASH DAY (today)
# ============================================
# Replays a real day of the cash book on Date.current, through the same
# services caja uses, so the day screen always has a full, open day to work on.
puts "\n🧾 Cargando el día de caja de hoy..."

hoy = Date.current

seed_or_raise = lambda do |label, result|
  raise "Seeds de caja: #{label} — #{result.errors.join(', ')}" if result.failure?

  result.record
end

# Pending non-supplier debts: taxes, social charges and a utility, all in ARS.
afip   = Supplier.create!(name: "AFIP")
edesur = Supplier.create!(name: "Edesur")
seed_or_raise.("factura IIBB", Invoices::CreateInvoice.call(
  supplier: afip, invoice_number: "IIBB 09/2026", amount: 250_000, currency: "ARS",
  purchase_date: Date.current - 5, due_date: Date.current + 9, expense_type: "taxes"))
seed_or_raise.("factura F931", Invoices::CreateInvoice.call(
  supplier: afip, invoice_number: "F931 09/2026", amount: 226_000, currency: "ARS",
  purchase_date: Date.current - 5, due_date: Date.current + 4, expense_type: "social_charges"))
seed_or_raise.("factura Edesur", Invoices::CreateInvoice.call(
  supplier: edesur, invoice_number: "Edesur 0921", amount: 48_300, currency: "ARS",
  purchase_date: Date.current - 3, due_date: Date.current + 12, expense_type: "utilities"))

# Single-unit lines priced so each note adds up to the amount on paper.
crear_nota = lambda do |paper_number:, precios:, order_type: "immediate", customer: mostrador,
                        sale_date: hoy, contact_name: nil, contact_phone: nil|
  items = productos.sample(precios.size).zip(precios).map do |producto, precio|
    { product_id: producto.id, quantity: 1, unit_price: precio }
  end

  seed_or_raise.("nota #{paper_number}", Sales::CreateOrder.call(
    customer: customer, user: seller_user, items: items, order_type: order_type,
    paper_number: paper_number, channel: "counter", source: "from_paper", sale_date: sale_date,
    contact_name: contact_name, contact_phone: contact_phone
  ))
end

cobrar_nota = lambda do |paper_number, tenders, precios: nil, discount_percent: 0|
  precios ||= [ tenders.sum { |t| t[:amount] } ]
  order = crear_nota.(paper_number: paper_number, precios: precios)
  seed_or_raise.("cobro #{paper_number}", Payments::CollectSaleNote.call(
    order: order, tenders: tenders, user: cashier_user, discount_percent: discount_percent, payment_date: hoy
  ))
end

cobrar_a_cuenta = lambda do |order, amount, payment_date: hoy|
  seed_or_raise.("cobro a cuenta #{order.paper_number}", Payments::CollectOnAccount.call(
    order: order, user: cashier_user, payment_date: payment_date,
    tenders: [ { payment_method: "mercado_pago", amount: amount } ]
  ))
end

transferir = lambda do |amount, description: nil|
  seed_or_raise.("transferencia", Cash::RecordTransfer.call(
    from: "mercado_pago", to: "bank", amount: amount, business_date: hoy, user: cashier_user,
    description: description
  ))
end

pagar_del_cajon = lambda do |amount, description|
  seed_or_raise.(description, Cash::RecordMovement.call(
    business_date: hoy, account: "drawer", amount: -amount, category: "suppliers",
    description: description, user: cashier_user
  ))
end

efectivo = ->(amount) { { payment_method: "cash", amount: amount } }
mercado_pago = ->(amount) { { payment_method: "mercado_pago", amount: amount } }

admin_user = User.find_by(role: "admin") || User.first!
{ "main_cash" => 2_500_000, "change_fund" => 103_300, "mercado_pago" => 1_500_000, "bank" => 800_000 }
  .each do |account, amount|
    seed_or_raise.("saldo inicial #{account}", Cash::RecordMovement.call(
      business_date: hoy - 30, account: account, amount: amount, category: "opening_balance",
      description: "Saldo inicial", user: admin_user
    ))
  end

jorge = FactoryBot.create(:customer, :with_credit, name: "Jorge Almaraz", phone: "11-5678-4411")
nota_jorge = crear_nota.(paper_number: "4411", precios: [ 32_000 ], order_type: "credit",
                         customer: jorge, sale_date: hoy - 5)
nota_diego = crear_nota.(paper_number: "4242", precios: [ 42_840, 35_000, 68_200, 27_160 ],
                         order_type: "on_account", sale_date: hoy - 14,
                         contact_name: "DIEGO", contact_phone: "11-6452-4796")
nota_walter = crear_nota.(paper_number: "4426", precios: [ 75_000, 45_000 ], order_type: "on_account",
                          sale_date: hoy - 3, contact_name: "Walter", contact_phone: "11-6123-4426")
cobrar_a_cuenta.(nota_diego, 80_000, payment_date: hoy - 14)

# Today, in the order caja loaded it.
seed_or_raise.("cobranza 4411", Payments::AllocatePayment.call(
  customer: jorge, payment_date: hoy, user: cashier_user,
  allocations: [ { order_id: nota_jorge.id, amount: 32_000, payment_method: "cash" } ]
))
cobrar_nota.("4419", [ efectivo.(34_200) ])
transferir.(900_000)
cobrar_nota.("4382", [ mercado_pago.(84_200) ])
cobrar_nota.("4420", [ mercado_pago.(45_000) ])
cobrar_nota.("4381", [ efectivo.(16_700) ])
cobrar_nota.("4421", [ efectivo.(150_000), mercado_pago.(186_600) ])
cobrar_a_cuenta.(nota_diego, 93_200)
cobrar_nota.("4424", [ efectivo.(7_000) ])
cobrar_a_cuenta.(nota_walter, 50_000)
transferir.(180_000, description: "BALANCE")
pagar_del_cajon.(33_500, "COMPRA DE PIPETA EN SIR MOTOR")
cobrar_nota.("4427", [ efectivo.(104_400) ], precios: [ 116_000 ], discount_percent: 10)
cobrar_nota.("4428", [ efectivo.(15_000) ])
cobrar_nota.("4429", [ mercado_pago.(264_100) ])
cobrar_nota.("4430", [ mercado_pago.(44_900) ])
pagar_del_cajon.(302_800, "PAGO DM RE-896441 RE-242795")

# Invoiced the way the spreadsheet shows it; 4411 and 4429 stay unbilled.
facturas_b = { "4420" => "1450", "4382" => "1451", "4421" => "1452", "4242" => "1453",
               "4426" => "1454", "4430" => "1456" }
CashMovement.on(hoy).where("amount > 0").where.not(source_payment_id: nil)
            .includes(source_payment: :orders).each do |movimiento|
  pago = movimiento.source_payment
  nota = pago.orders.map(&:paper_number).min
  next if %w[4411 4429].include?(nota)

  tipo, numero = pago.payment_method == "cash" ? [ "none", nil ] : [ "b", facturas_b.fetch(nota) ]
  seed_or_raise.("factura #{nota}", Payments::AssignInvoice.call(payment: pago, invoice_type: tipo,
                                                                 invoice_number: numero))
end

dia = Cash::DayQuery.new(hoy)
puts "✅ Día #{hoy.strftime('%d/%m/%Y')} abierto: #{CashMovement.on(hoy).count} movimientos | " \
     "ventas $#{dia.sales_by_channel.values.sum.to_i} | a fajar $#{dia.amount_to_wrap.to_i}"

# ============================================
# 10. FINAL STATISTICS
# ============================================
puts "\n" + "="*60
puts "📊 ESTADÍSTICAS FINALES"
puts "="*60


puts "\n📦 Productos:"
puts "  Total: #{Product.count}"
puts "  OEM Japan: #{Product.where(product_type: 'oem', origin: 'japan').count}"
puts "  OEM USA: #{Product.where(product_type: 'oem', origin: 'usa').count}"
puts "  Aftermarket: #{Product.where(product_type: 'aftermarket').count}"
puts "  Stock total: #{Product.sum(:current_stock)} unidades"
puts "  Valor inventario: $#{(Product.sum('current_stock * price_unit')).to_i}"
puts "  Con stock bajo (<5): #{Product.with_low_stock.count}"
puts "  Sin stock: #{Product.where(current_stock: 0).count}"
puts "  Con ubicación asignada: #{Product.where.not(location_code: nil).count}"
puts "  Sin ubicación: #{Product.where(location_code: nil).count}"

puts "\n🏭 Proveedores: #{Supplier.count}"

puts "\n👥 Clientes:"
puts "  Total: #{Customer.count}"
puts "  Con cuenta corriente: #{Customer.where(has_credit_account: true).count}"
clientes_con_saldo = Customer.where(has_credit_account: true).select { |c| c.current_balance > 0 }
puts "  Con saldo pendiente: #{clientes_con_saldo.count}"
if clientes_con_saldo.any?
  puts "  Saldo total a cobrar: $#{clientes_con_saldo.sum(&:current_balance).to_i}"
end

puts "\n📦 Compras (full mode):"
puts "  Total: #{Invoice.full_mode.count}"
puts "  Items: #{InvoiceItem.count}"
puts "  Unidades compradas: #{InvoiceItem.sum(:quantity)}"

puts "\n📄 Facturas simples (pending view):"
puts "  Total: #{Invoice.simple_mode.count}"
puts "  Pendientes: #{Invoice.simple_mode.pending_payment.count}"
puts "  Vencen esta semana: #{Invoice.due_this_week.count}"
puts "  Vencen semana próxima: #{Invoice.due_next_week.count}"
puts "  Con descuento anticipado: #{Invoice.discount_available.count}"
puts "  Vencidas: #{Invoice.overdue.count}"
puts "  Pagadas: #{Invoice.simple_mode.paid_invoices.count}"

puts "\n📝 Notas de Crédito:"
puts "  Total: #{CreditNote.count}"
puts "  Activas: #{CreditNote.available.count}"
puts "  Saldo total disponible: $#{CreditNote.available.sum { |cn| cn.remaining_balance_ars }.to_i}"

puts "\n💰 Ventas:"
puts "  Total: #{Order.where.not(status: 'cancelled').count}"
puts "  Contado: #{Order.where(order_type: 'immediate').where.not(status: 'cancelled').count}"
puts "  Crédito: #{Order.where(order_type: 'credit').where.not(status: 'cancelled').count}"
puts "  Pago a cuenta: #{Order.where(order_type: 'on_account').where.not(status: 'cancelled').count} (abiertas: #{Order.open_on_account.length})"
puts "  Items vendidos: #{OrderItem.sum(:quantity)}"
puts "  Total facturado: $#{Order.where.not(status: 'cancelled').sum(:total_amount).to_i}"

puts "\n💵 Pagos:"
puts "  Total: #{Payment.count}"
puts "  Monto cobrado: $#{Payment.sum(:amount).to_i}"

puts "\n📊 Movimientos de Stock:"
puts "  Total: #{StockMovement.count}"
puts "  Compras (+): #{StockMovement.where(movement_type: 'purchase').sum(:quantity)}"
puts "  Ventas (-): #{StockMovement.where(movement_type: 'sale').sum(:quantity).abs}"

puts "\n" + "="*60
puts "✅ SEEDS COMPLETADOS!"
puts "="*60
puts "\n💡 Tip: Ejecutá 'rails db:reset' para limpiar y volver a crear\n\n"
