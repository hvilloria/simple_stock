class AddOrderTypeToOrders < ActiveRecord::Migration[7.2]
  def change
    add_column :orders, :order_type, :string, default: 'cash', null: false
    add_index :orders, :order_type
  end
end
