class CreateDailyClosings < ActiveRecord::Migration[7.2]
  def change
    create_table :daily_closings do |t|
      t.date :business_date, null: false
      t.decimal :expected_cash, precision: 10, scale: 2, null: false
      t.decimal :counted_cash, precision: 10, scale: 2, null: false
      t.decimal :payway_batch_total, precision: 10, scale: 2
      t.decimal :mercado_pago_total, precision: 10, scale: 2
      t.references :user, null: false, foreign_key: true
      t.datetime :closed_at, null: false

      t.timestamps
    end

    add_index :daily_closings, :business_date, unique: true
  end
end
