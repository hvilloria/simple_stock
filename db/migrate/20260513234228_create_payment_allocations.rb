class CreatePaymentAllocations < ActiveRecord::Migration[7.2]
  def change
    create_table :payment_allocations do |t|
      t.references :payment, null: false, foreign_key: true
      t.references :order,   null: false, foreign_key: true
      t.decimal :amount, precision: 10, scale: 2, null: false

      t.timestamps
    end

    add_index :payment_allocations, [ :payment_id, :order_id ], unique: true

    remove_index :payments, :order_id if index_exists?(:payments, :order_id)
    remove_column :payments, :order_id, :bigint
  end
end
