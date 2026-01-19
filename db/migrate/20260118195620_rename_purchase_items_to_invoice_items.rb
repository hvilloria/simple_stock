class RenamePurchaseItemsToInvoiceItems < ActiveRecord::Migration[7.2]
  def change
    rename_table :purchase_items, :invoice_items
  end
end
