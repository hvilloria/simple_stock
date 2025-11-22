class CreatePayments < ActiveRecord::Migration[7.2]
  def change
    create_table :payments do |t|
      t.references :customer, null: false, foreign_key: true, index: true
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.string :payment_method, null: false
      t.date :payment_date, null: false, default: -> { "CURRENT_DATE" }
      t.text :notes

      t.timestamps

      t.index :payment_date
    end
  end
end
