namespace :inventory do
  desc "Sincronizar productos y stock desde archivo CSV"
  task :sync_from_csv, [ :file_path ] => :environment do |t, args|
    file_path = args[:file_path] || Rails.root.join("db", "bootstrap", "products_inventory.csv")

    unless File.exist?(file_path)
      puts "❌ Archivo no encontrado: #{file_path}"
      puts "💡 Uso: rails inventory:sync_from_csv['/path/to/archivo.csv']"
      exit 1
    end

    puts "\n" + "="*80
    puts "📊 INVENTORY SYNC FROM CSV"
    puts "="*80
    puts "File: #{file_path}"
    puts "Started at: #{Time.current}"
    puts "="*80 + "\n"

    result = Inventory::SyncFromCsv.call(file_path: file_path.to_s)

    if result.success?
      puts "\n✅ Sincronización completada exitosamente"
      puts "📄 Log guardado en: #{result.record[:log_path]}"
    else
      puts "\n⚠️  Sincronización completada con errores"
      puts "📄 Log guardado en: #{result.record[:log_path]}" if result.record
      puts "\nErrores:"
      result.errors.each { |error| puts "  - #{error}" }
    end
  end
end
