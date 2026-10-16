class AddVoidToPayments < ActiveRecord::Migration[7.2]
  def change
    add_column :payments, :status, :string, null: false, default: "active"
    add_column :payments, :voided_at, :datetime
    add_reference :payments, :voided_by, foreign_key: { to_table: :users }
    add_column :payments, :void_reason, :text
    add_index :payments, :status

    create_table :voided_payment_allocations do |t|
      t.references :payment, null: false, foreign_key: true
      t.references :order, null: false, foreign_key: true
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.decimal :discount_amount, precision: 10, scale: 2, null: false, default: 0
      t.decimal :overpaid_amount, precision: 10, scale: 2, null: false, default: 0
      t.timestamps
    end
  end
end
