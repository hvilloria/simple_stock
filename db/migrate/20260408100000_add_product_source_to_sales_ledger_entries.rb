# frozen_string_literal: true

class AddProductSourceToSalesLedgerEntries < ActiveRecord::Migration[7.2]
  def change
    add_column :sales_ledger_entries, :product_source, :string
    add_index  :sales_ledger_entries, :product_source
  end
end
