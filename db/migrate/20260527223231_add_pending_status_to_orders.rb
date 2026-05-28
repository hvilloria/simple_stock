class AddPendingStatusToOrders < ActiveRecord::Migration[7.2]
  def change
    change_column_default :orders, :status, from: "confirmed", to: "pending"
  end
end
