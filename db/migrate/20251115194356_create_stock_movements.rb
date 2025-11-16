class CreateStockMovements < ActiveRecord::Migration[7.2]
  def change
    create_table :stock_movements do |t|
      t.references :product,        null: false, foreign_key: true
      t.references :stock_location, null: false, foreign_key: true

      t.integer :quantity,      null: false
      t.string  :movement_type, null: false
      t.string  :reference
      t.text    :note

      t.timestamps
    end

    add_index :stock_movements, :movement_type
  end
end
