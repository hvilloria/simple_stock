class CreateCombos < ActiveRecord::Migration[7.2]
  def change
    add_column :products, :combo, :boolean, null: false, default: false
    add_index :products, :combo

    create_table :combo_components do |t|
      t.references :combo, null: false, index: false, foreign_key: { to_table: :products }
      t.references :product, null: false, foreign_key: true
      t.integer :quantity, null: false
      t.timestamps
    end

    add_index :combo_components, %i[combo_id product_id], unique: true
    add_check_constraint :combo_components, "quantity > 0", name: "combo_components_quantity_positive"

    create_table :order_item_components do |t|
      t.references :order_item, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: true
      t.integer :quantity, null: false
      t.timestamps
    end

    add_check_constraint :order_item_components, "quantity > 0", name: "order_item_components_quantity_positive"
  end
end
