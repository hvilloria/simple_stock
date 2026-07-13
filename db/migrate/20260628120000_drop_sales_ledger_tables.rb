class DropSalesLedgerTables < ActiveRecord::Migration[7.2]
  def up
    # Drop the child table first (it holds the FK to sales_imports).
    # FKs to products/users are removed automatically with the table.
    drop_table :sales_ledger_entries
    drop_table :sales_imports
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
