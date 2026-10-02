# frozen_string_literal: true

class RemoveInvoiceFromOrders < ActiveRecord::Migration[7.2]
  def change
    remove_index :orders, :invoice_type
    remove_column :orders, :invoice_number, :string
    remove_column :orders, :invoice_type, :string
  end
end
