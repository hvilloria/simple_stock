class CreatePurchases < ActiveRecord::Migration[7.2]
  def change
    create_table :purchases do |t|
      t.references :supplier, null: false, foreign_key: true
      t.string :currency, null: false, default: "USD"
      t.decimal :exchange_rate, precision: 10, scale: 4
      t.date :purchase_date, null: false
      t.string :status, null: false, default: "confirmed"
      t.decimal :total_cost, precision: 10, scale: 2
      t.text :notes

      t.timestamps
    end

    add_index :purchases, :purchase_date
  end
end
