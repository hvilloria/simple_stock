class AddUserToOrders < ActiveRecord::Migration[7.2]
  def change
    add_reference :orders, :user, null: false, foreign_key: { on_delete: :restrict }
  end
end
