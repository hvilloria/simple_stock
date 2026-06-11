class AddDeliveredAtToOrderItems < ActiveRecord::Migration[7.2]
  def change
    add_column :order_items, :delivered_at, :datetime
  end
end
