# frozen_string_literal: true

class AddInvoiceToPayments < ActiveRecord::Migration[7.2]
  def change
    add_column :payments, :invoice_type, :string
    add_column :payments, :invoice_number, :string
  end
end
