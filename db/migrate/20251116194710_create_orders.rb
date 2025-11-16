class CreateOrders < ActiveRecord::Migration[7.2]
  def change
    create_table :orders do |t|
      t.string :status, null: false, default: "confirmed"
      t.decimal :total_amount, precision: 10, scale: 2, null: false, default: 0
      t.references :customer, null: true, foreign_key: true

      t.timestamps
    end

    add_index :orders, :status
  end
end
