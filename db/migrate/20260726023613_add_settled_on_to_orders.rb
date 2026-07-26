class AddSettledOnToOrders < ActiveRecord::Migration[7.2]
  def up
    add_column :orders, :settled_on, :date
    add_index :orders, :settled_on

    execute <<~SQL
      UPDATE orders
      SET settled_on = sub.last_payment_date
      FROM (
        SELECT pa.order_id, MAX(p.payment_date) AS last_payment_date
        FROM payment_allocations pa
        JOIN payments p ON p.id = pa.payment_id
        GROUP BY pa.order_id
      ) AS sub
      WHERE orders.id = sub.order_id
        AND orders.settled_on IS NULL
        AND orders.status <> 'cancelled'
        AND orders.total_amount - COALESCE(
          (SELECT SUM(amount) FROM payment_allocations WHERE order_id = orders.id), 0
        ) <= 0
    SQL
  end

  def down
    remove_column :orders, :settled_on
  end
end
