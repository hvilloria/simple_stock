class CreateStockLocations < ActiveRecord::Migration[7.2]
  def change
    create_table :stock_locations do |t|
      t.string :name, null: false
      t.string :code
      t.string :address

      t.timestamps
    end
  end
end
