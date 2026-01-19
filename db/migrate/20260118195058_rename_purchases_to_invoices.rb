class RenamePurchasesToInvoices < ActiveRecord::Migration[7.2]
  def change
    rename_table :purchases, :invoices
  end
end
