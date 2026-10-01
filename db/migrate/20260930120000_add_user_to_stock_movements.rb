class AddUserToStockMovements < ActiveRecord::Migration[7.2]
  def change
    add_reference :stock_movements, :user, null: true, foreign_key: true
  end
end
