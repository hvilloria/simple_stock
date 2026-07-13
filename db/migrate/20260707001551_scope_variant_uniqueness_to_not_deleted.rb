class ScopeVariantUniquenessToNotDeleted < ActiveRecord::Migration[7.2]
  def change
    remove_index :products, name: "index_products_on_variant_uniqueness"
    add_index :products,
              [ :sku, :product_type, :brand, :origin ],
              unique: true,
              where: "deleted_at IS NULL",
              name: "index_products_on_variant_uniqueness"
  end
end
