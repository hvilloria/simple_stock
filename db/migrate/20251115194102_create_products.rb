class CreateProducts < ActiveRecord::Migration[7.2]
  def change
    create_table :products do |t|
      t.string :name, null: false
      t.string :sku, null: false
      t.string :category
      t.decimal :cost_unit, precision: 10, scale: 2
      t.decimal :price_unit, precision: 10, scale: 2
      t.integer :current_stock, null: false, default: 0
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :products, :sku, unique: true
  end
end
