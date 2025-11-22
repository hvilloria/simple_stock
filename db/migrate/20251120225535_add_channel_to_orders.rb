class AddChannelToOrders < ActiveRecord::Migration[7.2]
  def change
    add_column :orders, :channel, :string
  end
end
