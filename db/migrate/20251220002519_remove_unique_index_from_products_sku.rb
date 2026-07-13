class RemoveUniqueIndexFromProductsSku < ActiveRecord::Migration[7.2]
  def change
    # Remove the existing unique index on sku
    remove_index :products, :sku

    # Add a normal index for fast lookups by OEM code
    add_index :products, :sku

    # Add a composite unique index to prevent duplicating the same exact variant
    # This allows multiple variants of the same OEM (sku), but not duplicating
    # the same combination of sku + type + brand + origin
    add_index :products,
              [ :sku, :product_type, :brand, :origin ],
              unique: true,
              name: 'index_products_on_variant_uniqueness'
  end
end
