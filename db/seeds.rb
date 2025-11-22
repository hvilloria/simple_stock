# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

puts "Seeding database..."

# Cliente genérico para ventas de mostrador (contado)
mostrador = Customer.find_or_create_by!(name: "Cliente Mostrador") do |c|
  c.customer_type = "retail"
  c.has_credit_account = false
end

puts "✓ Cliente Mostrador creado (ID: #{mostrador.id})"

# Datos de ejemplo para development
if Rails.env.development?
  puts "\nCreando datos de ejemplo para compras..."

  # Crear proveedor
  supplier = Supplier.find_or_create_by!(name: "Import USA Parts") do |s|
    s.contact_name = "John Doe"
    s.email = "orders@importusa.com"
    s.phone = "+1-555-0100"
    s.address = "123 Import St, Miami, FL 33101"
  end

  puts "✓ Proveedor creado: #{supplier.name}"

  # Crear compra de ejemplo solo si hay productos y no hay compras
  if Product.count > 0 && Purchase.count == 0
    products = Product.limit(3)

    result = Purchasing::CreatePurchase.call(
      supplier: supplier,
      items: products.map { |p| { product_id: p.id, quantity: 50, unit_cost: 30.0 } },
      currency: "USD",
      exchange_rate: 1200,
      notes: "Compra inicial de ejemplo"
    )

    if result.success?
      puts "✓ Compra de ejemplo creada (ID: #{result.record.id})"
    else
      puts "✗ Error creando compra: #{result.errors.join(', ')}"
    end
  end

  # Crear datos de ejemplo para pagos
  puts "\nCreando datos de ejemplo para pagos..."

  # Buscar un cliente con cuenta corriente y saldo
  customer = Customer.with_credit_account.first

  if customer && customer.current_balance > 0
    result = Payments::RegisterPayment.call(
      customer: customer,
      amount: customer.current_balance / 2, # Pago parcial
      payment_method: "transfer",
      notes: "Pago de ejemplo"
    )

    if result.success?
      puts "✓ Pago de ejemplo creado (ID: #{result.record.id})"
      puts "  Cliente: #{customer.name}"
      puts "  Monto: $#{result.record.amount}"
      puts "  Saldo restante: $#{customer.reload.current_balance}"
    else
      puts "✗ Error creando pago: #{result.errors.join(', ')}"
    end
  else
    puts "⚠ No hay clientes con saldo para crear pago de ejemplo"
  end
end

puts "\nDatabase seeded successfully!"
