class AddEarlyPaymentFieldsToSuppliers < ActiveRecord::Migration[7.2]
  def change
    add_column :suppliers, :early_payment_days, :integer
    add_column :suppliers, :early_payment_discount_percentage, :decimal, precision: 5, scale: 2
  end
end
