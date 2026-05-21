class AddDiscountToOrdersAndItems < ActiveRecord::Migration[7.2]
  def up
    add_column :order_items, :discount_percent, :decimal, precision: 5, scale: 2, default: 0, null: false
    add_column :orders, :original_total_amount, :decimal, precision: 10, scale: 2

    # Backfill any existing rows (seeds, dev) so original_total_amount mirrors total_amount.
    execute "UPDATE orders SET original_total_amount = total_amount WHERE original_total_amount IS NULL"

    change_column_null :orders, :original_total_amount, false
  end

  def down
    remove_column :orders, :original_total_amount
    remove_column :order_items, :discount_percent
  end
end
