class AddSupplierToCashMovements < ActiveRecord::Migration[7.2]
  def change
    add_reference :cash_movements, :supplier, foreign_key: true
  end
end
