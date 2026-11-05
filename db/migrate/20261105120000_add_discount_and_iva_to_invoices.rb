class AddDiscountAndIvaToInvoices < ActiveRecord::Migration[7.2]
  def change
    add_column :invoices, :discount_percentage, :decimal, precision: 5, scale: 2
    add_column :invoices, :iva_percentage, :decimal, precision: 5, scale: 2

    add_column :invoice_items, :final_unit_cost, :decimal, precision: 10, scale: 2
    add_column :invoice_items, :previous_cost_unit, :decimal, precision: 10, scale: 2
    add_column :invoice_items, :previous_cost_currency, :string
  end
end
