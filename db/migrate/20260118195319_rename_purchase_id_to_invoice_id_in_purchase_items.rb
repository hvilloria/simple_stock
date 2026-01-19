class RenamePurchaseIdToInvoiceIdInPurchaseItems < ActiveRecord::Migration[7.2]
  def change
    rename_column :purchase_items, :purchase_id, :invoice_id
  end
end
