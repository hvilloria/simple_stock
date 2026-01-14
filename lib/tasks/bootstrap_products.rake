# lib/tasks/bootstrap_products.rake
namespace :bootstrap do
  desc "Importar o actualizar catálogo base de productos desde CSV (db/bootstrap/products.csv)"
  task products: :environment do
    require "csv"

    path = Rails.root.join("db", "bootstrap", "products.csv")
    unless File.exist?(path)
      puts "No se encontró el archivo #{path}"
      exit 1
    end

    puts "Importando productos desde #{path}..."

    created = 0
    updated = 0
    errors  = []

    CSV.foreach(path, headers: true) do |row|
      sku = row["sku"]&.strip

      if sku.blank?
        errors << "Fila sin SKU, se omite: #{row.inspect}"
        next
      end

      name         = row["name"]&.strip
      category     = row["category"]&.strip
      product_type = row["product_type"]&.strip
      origin       = row["origin"]&.strip
      brand        = row["brand"]&.strip
      price_unit   = row["price_unit"].presence && row["price_unit"].to_d
      active       = case row["active"].to_s.strip.downcase
      when "false", "0", "no" then false
      when "true", "1", "si", "sí" then true
      else
                       nil # usa default del modelo (true)
      end

      product = Product.find_or_initialize_by(sku: sku)

      product.name         = name if name.present?
      product.category     = category.presence
      product.product_type = product_type.presence
      product.origin       = origin.presence
      product.brand        = brand.presence
      product.price_unit   = price_unit if price_unit
      product.active       = active unless active.nil?

      begin
        if product.new_record?
          product.save!
          created += 1
          puts "Creado: #{product.sku} - #{product.name}"
        else
          if product.changed?
            product.save!
            updated += 1
            puts "Actualizado: #{product.sku} - #{product.name}"
          else
            # sin cambios, no hace falta guardar
          end
        end
      rescue ActiveRecord::RecordInvalid => e
        errors << "Error en SKU #{sku}: #{e.record.errors.full_messages.join(", ")}"
      end
    end

    puts "Listo. Productos creados: #{created}, actualizados: #{updated}"
    if errors.any?
      puts "Errores encontrados:"
      errors.each { |msg| puts "  - #{msg}" }
    end
  end
end
