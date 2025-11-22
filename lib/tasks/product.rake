# frozen_string_literal: true

namespace :product do
  desc "Recalcular costo promedio de todos los productos"
  task recalculate_costs: :environment do
    puts "Recalculando costos promedio..."

    count = 0
    Product.find_each do |product|
      product.recalculate_average_cost!
      count += 1
      print "." if (count % 100).zero?
    end

    puts "\n✓ #{count} productos actualizados"
  end

  desc "Recalcular costo promedio de un producto específico (uso: rake product:recalculate_cost[SKU123])"
  task :recalculate_cost, [ :sku ] => :environment do |_t, args|
    product = Product.find_by(sku: args[:sku])

    if product
      old_cost = product.cost_unit
      old_currency = product.cost_currency
      product.recalculate_average_cost!
      new_cost = product.cost_unit
      new_currency = product.cost_currency

      puts "Producto: #{product.name}"
      puts "Costo anterior: #{old_cost} #{old_currency}"
      puts "Costo nuevo: #{new_cost} #{new_currency}"
    else
      puts "Producto no encontrado: #{args[:sku]}"
    end
  end
end
