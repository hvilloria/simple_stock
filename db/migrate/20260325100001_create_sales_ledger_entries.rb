# frozen_string_literal: true

class CreateSalesLedgerEntries < ActiveRecord::Migration[7.2]
  def change
    create_table :sales_ledger_entries do |t|
      t.references :sales_import, null: false, foreign_key: true
      t.date    :sale_date,              null: false
      t.string  :ticket_number,          null: false
      t.string  :oem_code,               null: false
      t.string  :product_name_snapshot,  null: false
      t.integer :quantity,               null: false
      t.decimal :unit_price,             precision: 10, scale: 2, null: false
      t.decimal :total_amount,           precision: 10, scale: 2, null: false
      t.references :product,             null: false, foreign_key: true
      t.string  :entry_fingerprint,      null: false
      t.jsonb   :raw_row_data
      t.timestamps
    end

    add_index :sales_ledger_entries, :entry_fingerprint, unique: true
    add_index :sales_ledger_entries, :sale_date
    add_index :sales_ledger_entries, :ticket_number
    add_index :sales_ledger_entries, :oem_code
  end
end
