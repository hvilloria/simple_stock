# db/seeds.rb

# Limpiar solo en development
if Rails.env.development?
  puts "🗑️  Limpiando datos existentes..."
  [ Payment, OrderItem, Order, InvoiceItem, AppliedCredit, CreditNote,
    Invoice, StockMovement, Product, Customer, Supplier, StockLocation, User ].each(&:destroy_all)
  puts "✅ Base de datos limpiada"
end

# ============================================
# 0. USUARIOS
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

  puts "✅ Usuario admin creado:"
  puts "   Email: #{admin.email}"
  puts "   Password: password123"
  puts "   ⚠️  CAMBIAR PASSWORD EN PRODUCCIÓN"
else
  puts "✅ Usuarios ya existen, saltando creación"
end

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
# 2. PROVEEDORES (5)
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
# 3. CLIENTES
# ============================================
puts "\n👥 Creando clientes..."

# Cliente Mostrador
mostrador = Customer.find_or_create_by!(name: "Cliente Mostrador") do |c|
  c.customer_type = "retail"
  c.has_credit_account = false
end

# Talleres con nombres argentinos realistas
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

# Cliente particular
particular = FactoryBot.create(:customer, :with_credit,
  name: "Juan Pérez",
  document: "20-35678901-2",
  phone: "11-5678-9012",
  customer_type: "retail"
)

clientes_con_credito = talleres + [ particular ]
puts "✅ Cliente Mostrador + #{clientes_con_credito.count} clientes con cuenta corriente"

# ============================================
# 4. PRODUCTOS (200 productos Honda variados)
# ============================================
puts "\n🔧 Creando 200 productos Honda..."

# Nombres realistas por categoría
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

    # Determinar tipo, origen y marca (40% OEM Japan, 20% OEM USA, 40% Aftermarket)
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
      # Aftermarket (distribuir orígenes y marcas)
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

    # Calcular precio en ARS
    exchange_rate = rand(1150..1250)
    price_ars = (cost_usd * exchange_rate * price_multiplier * rand(1.3..1.9)).round(0)

    # Generar ubicación física válida: [pasillo 1-9][lado I/D][posición 0-9][nivel 0-9]
    # 80% de los productos tienen ubicación, 20% sin asignar
    location_code = if rand(100) < 80
      pasillo = rand(1..9)
      lado = [ 'I', 'D' ].sample
      posicion = rand(0..9)
      nivel = rand(0..4)  # Niveles 0-4 (5 niveles máximo)
      "#{pasillo}#{lado}#{posicion}#{nivel}"
    else
      nil  # Sin ubicación asignada
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
# 5. COMPRAS (20 compras en últimos 30 días)
# ============================================
puts "\n📦 Creando compras..."

compras_exitosas = 0
20.times do |i|
  supplier = suppliers.sample
  fecha = rand(30).days.ago.to_date

  # 5-15 productos aleatorios
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
# 6. VENTAS (50 ventas en últimos 7 días)
# ============================================
puts "\n💰 Creando ventas (esto puede tardar un poco)..."

ventas_exitosas = 0
ventas_fallidas = 0

# 45 ventas de mostrador
45.times do
  fecha = rand(7).days.ago + rand(24).hours

  productos_con_stock = productos.select { |p| p.reload.current_stock > 0 }
  next if productos_con_stock.empty?

  productos_venta = productos_con_stock.sample(rand(1..4))

  items = productos_venta.map do |producto|
    producto.reload
    cantidad = [ rand(1..5), producto.current_stock ].min
    next if cantidad <= 0

    {
      product_id: producto.id,
      quantity: cantidad,
      unit_price: producto.price_unit
    }
  end.compact

  next if items.empty?

  result = Sales::CreateOrder.call(
    customer: mostrador,
    items: items,
    order_type: "cash",
    channel: [ 'counter', 'whatsapp', 'mercadolibre' ].sample
  )

  if result.success?
    result.record.update_column(:created_at, fecha)
    ventas_exitosas += 1
    print "."
  else
    ventas_fallidas += 1
  end
end

# 5 ventas a crédito
5.times do
  fecha = rand(7).days.ago + rand(24).hours
  cliente = clientes_con_credito.sample

  productos_con_stock = productos.select { |p| p.reload.current_stock > 5 }
  next if productos_con_stock.empty?

  productos_venta = productos_con_stock.sample(rand(2..5))

  items = productos_venta.map do |producto|
    producto.reload
    cantidad = [ rand(2..8), producto.current_stock - 2 ].min
    next if cantidad <= 0

    {
      product_id: producto.id,
      quantity: cantidad,
      unit_price: producto.price_unit
    }
  end.compact

  next if items.empty?

  result = Sales::CreateOrder.call(
    customer: cliente,
    items: items,
    order_type: "credit",
    channel: "counter"
  )

  if result.success?
    result.record.update_column(:created_at, fecha)
    ventas_exitosas += 1
    print "."
  else
    ventas_fallidas += 1
  end
end

puts "\n✅ #{ventas_exitosas} ventas creadas (#{ventas_fallidas} omitidas por stock)"

# ============================================
# 7. PAGOS (2-3 pagos parciales)
# ============================================
puts "\n💵 Registrando pagos..."

pagos_creados = 0
clientes_con_credito.each do |cliente|
  saldo = cliente.current_balance

  if saldo > 1000
    monto = (saldo * rand(0.3..0.7)).round(0)
    metodo = [ 'cash', 'transfer', 'check' ].sample
    fecha_pago = rand(3).days.ago.to_date

    result = Payments::RegisterPayment.call(
      customer: cliente,
      amount: monto,
      payment_method: metodo,
      payment_date: fecha_pago,
      notes: "Pago parcial - #{metodo}"
    )

    if result.success?
      result.record.update_column(:created_at, fecha_pago.to_time + rand(9..17).hours)
      pagos_creados += 1
      puts "  ✓ #{cliente.name}: $#{monto.to_i} | Saldo: $#{cliente.reload.current_balance.to_i}"
    end
  end
end

puts "✅ #{pagos_creados} pagos registrados"

# ============================================
# 8. FACTURAS SIMPLES PENDIENTES
# ============================================
puts "\n📄 Creando facturas simples pendientes (ARS)..."

inv_seq = 1
inv_ok  = 0

create_inv = ->(supplier, amount, purchase_date, due_date, opts = {}) do
  num = "SF-#{format('%04d', inv_seq)}"
  inv_seq += 1

  result = Invoices::CreateSimpleInvoice.call(
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

# ── Caso 1: Vencen esta semana ──────────────────────────────────────
puts "  → Esta semana (#{monday.strftime('%d/%m')} - #{(monday + 6).strftime('%d/%m')})..."

create_inv.(supplier_japan,   10_200_000, today - 30, monday + 1)
create_inv.(supplier_japan,   14_750_000, today - 25, monday + 3)
create_inv.(supplier_usa,      7_440_000, today - 20, monday + 2)
create_inv.(supplier_usa,     11_760_000, today - 28, monday + 4)
create_inv.(supplier_germany,  18_500_000, today - 22, monday + 1)
create_inv.(supplier_taiwan,    5_700_000, today - 18, monday + 3)
create_inv.(supplier_taiwan,    6_800_000, today - 15, monday + 5)
create_inv.(supplier_brazil,    6_120_000, today - 30, monday + 2)

# ── Caso 2: Vencen la semana próxima ────────────────────────────────
puts "  → Semana próxima (#{nxt_monday.strftime('%d/%m')} - #{(nxt_monday + 6).strftime('%d/%m')})..."

create_inv.(supplier_japan,   13_440_000, today - 10, nxt_monday + 1)
create_inv.(supplier_usa,      9_000_000, today - 8,  nxt_monday + 2)
create_inv.(supplier_usa,     21_600_000, today - 12, nxt_monday + 4)
create_inv.(supplier_germany,  11_160_000, today - 5,  nxt_monday + 1)
create_inv.(supplier_germany,  16_440_000, today - 15, nxt_monday + 3)
create_inv.(supplier_taiwan,    8_280_000, today - 7,  nxt_monday + 2)
create_inv.(supplier_brazil,    5_040_000, today - 9,  nxt_monday + 1)
create_inv.(supplier_brazil,    8_400_000, today - 11, nxt_monday + 4)

# ── Caso 3: Descuento anticipado vence esta semana (with_discount_to_advance) ──
puts "  → Con descuento anticipado (expira en #{today + 1}..#{today + 3})..."

create_inv.(supplier_japan,   26_400_000, today - 45, today + 30, ep_date: today + 2, ep_pct: 5)
create_inv.(supplier_usa,     17_400_000, today - 40, today + 25, ep_date: today + 1, ep_pct: 7)
create_inv.(supplier_germany,  37_200_000, today - 50, today + 35, ep_date: today + 2, ep_pct: 10)
create_inv.(supplier_taiwan,   11_760_000, today - 38, today + 28, ep_date: today + 1, ep_pct: 8)
create_inv.(supplier_brazil,   11_200_000, today - 42, today + 32, ep_date: today + 3, ep_pct: 6)

# ── Caso 4: Variedad adicional para la vista de índice ──────────────
puts "  → Variedad para el índice (vencidas, este mes, próximo mes)..."

# Vencidas
create_inv.(supplier_japan,    7_200_000, today - 60, today - 15)
create_inv.(supplier_usa,      5_760_000, today - 45, today - 7)
create_inv.(supplier_germany,  19_500_000, today - 30, today - 3)

# Este mes (fuera de esta semana y la próxima)
create_inv.(supplier_taiwan,    9_960_000, today - 5,  today + 14)
create_inv.(supplier_brazil,    6_720_000, today - 3,  today + 18)
create_inv.(supplier_japan,     8_640_000, today - 7,  today + 21)

# Próximo mes
create_inv.(supplier_usa,      13_200_000, today - 2,  today + 35)
create_inv.(supplier_germany,  20_160_000, today - 8,  today + 42)

# ── Pagadas (creadas y luego marcadas como paid) ─────────────────────
[
  [ supplier_japan,   22_200_000, today - 35 ],
  [ supplier_usa,     11_040_000, today - 28 ],
  [ supplier_germany, 28_800_000, today - 20 ],
  [ supplier_taiwan,   9_360_000, today - 42 ],
  [ supplier_brazil,  12_300_000, today - 15 ]
].each do |sup, amount, paid_date|
  num = "SF-#{format('%04d', inv_seq)}"
  inv_seq += 1

  result = Invoices::CreateSimpleInvoice.call(
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
# 9. ESTADÍSTICAS FINALES
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
puts "  Con descuento anticipado: #{Invoice.with_discount_to_advance.count}"
puts "  Vencidas: #{Invoice.overdue.count}"
puts "  Pagadas: #{Invoice.simple_mode.paid_invoices.count}"

puts "\n💰 Ventas:"
puts "  Total: #{Order.where.not(status: 'cancelled').count}"
puts "  Contado: #{Order.where(order_type: 'cash').where.not(status: 'cancelled').count}"
puts "  Crédito: #{Order.where(order_type: 'credit').where.not(status: 'cancelled').count}"
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
