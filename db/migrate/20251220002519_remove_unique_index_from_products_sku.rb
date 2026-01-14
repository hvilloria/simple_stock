class RemoveUniqueIndexFromProductsSku < ActiveRecord::Migration[7.2]
  def change
    # Eliminar el índice único existente sobre sku
    remove_index :products, :sku
    
    # Agregar índice normal para búsquedas rápidas por código OEM
    add_index :products, :sku
    
    # Agregar índice único compuesto para evitar duplicar la misma variante exacta
    # Esto permite múltiples variantes del mismo OEM (sku), pero no duplicar
    # la misma combinación de sku + tipo + marca + origen
    add_index :products, 
              [:sku, :product_type, :brand, :origin],
              unique: true,
              name: 'index_products_on_variant_uniqueness'
  end
end
