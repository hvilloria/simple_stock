# frozen_string_literal: true

class AddSellerAndPaymentToSalesLedgerEntries < ActiveRecord::Migration[7.2]
  def change
    add_column :sales_ledger_entries, :ticket_total_amount,    :decimal,  precision: 10, scale: 2
    add_column :sales_ledger_entries, :payment_method,         :string
    add_column :sales_ledger_entries, :seller_name,            :string
    add_column :sales_ledger_entries, :seller_user_id,         :bigint
    add_column :sales_ledger_entries, :ticket_amount_mismatch, :boolean,  default: false, null: false

    add_index :sales_ledger_entries, :payment_method
    add_index :sales_ledger_entries, :seller_name
    add_index :sales_ledger_entries, :seller_user_id
    add_foreign_key :sales_ledger_entries, :users, column: :seller_user_id, on_delete: :nullify
  end
end
