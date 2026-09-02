class CreateCashMovements < ActiveRecord::Migration[7.2]
  def change
    create_table :cash_movements do |t|
      t.date :business_date, null: false
      t.string :account
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.string :category, null: false
      t.string :subcategory
      t.string :channel
      t.string :description
      t.uuid :transfer_group_id
      t.references :daily_closing, foreign_key: true
      t.references :source_payment, foreign_key: { to_table: :payments }
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end

    add_index :cash_movements, :business_date
    add_index :cash_movements, :account
    add_index :cash_movements, :category
    add_index :cash_movements, :transfer_group_id
  end
end
