class AddCostSourceToProducts < ActiveRecord::Migration[7.2]
  def change
    add_reference :products, :cost_source_invoice_item,
                  foreign_key: { to_table: :invoice_items, on_delete: :nullify }
    add_reference :invoice_items, :previous_cost_source,
                  foreign_key: { to_table: :invoice_items, on_delete: :nullify }
  end
end
