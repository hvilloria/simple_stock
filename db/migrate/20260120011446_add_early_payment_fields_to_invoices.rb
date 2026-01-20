class AddEarlyPaymentFieldsToInvoices < ActiveRecord::Migration[7.2]
  def change
    add_column :invoices, :early_payment_due_date, :date
    add_column :invoices, :early_payment_discount_percentage, :decimal, precision: 5, scale: 2
    add_column :invoices, :paid_with_discount, :boolean, default: false

    add_index :invoices, :early_payment_due_date
  end
end
