class AddContactToOrders < ActiveRecord::Migration[7.2]
  def change
    add_column :orders, :contact_name, :string
    add_column :orders, :contact_phone, :string
  end
end
