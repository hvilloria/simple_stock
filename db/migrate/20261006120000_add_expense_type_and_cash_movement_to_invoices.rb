class AddExpenseTypeAndCashMovementToInvoices < ActiveRecord::Migration[7.2]
  def change
    add_column :invoices, :expense_type, :string, null: false, default: "supplier"
    add_index :invoices, :expense_type
    add_reference :invoices, :cash_movement, foreign_key: true, null: true
  end
end
