class AddInvoiceTypeToOrders < ActiveRecord::Migration[7.2]
  def change
    add_column :orders, :invoice_type, :string
    add_column :orders, :invoice_number, :string
    add_index :orders, :invoice_type
  end
end
