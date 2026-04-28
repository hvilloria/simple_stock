class RenameOrdersCashOrderTypeToImmediate < ActiveRecord::Migration[7.2]
  # `orders.order_type` is a plain string column (not a Postgres enum type),
  # so this migration only needs to rewrite the existing values. The Rails
  # enum mapping is updated in the Order model.
  def up
    execute <<~SQL.squish
      UPDATE orders
      SET order_type = 'immediate'
      WHERE order_type = 'cash'
    SQL

    change_column_default :orders, :order_type, from: "cash", to: "immediate"
  end

  def down
    change_column_default :orders, :order_type, from: "immediate", to: "cash"

    execute <<~SQL.squish
      UPDATE orders
      SET order_type = 'cash'
      WHERE order_type = 'immediate'
    SQL
  end
end
