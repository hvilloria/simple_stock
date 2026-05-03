class AddOrderToPayments < ActiveRecord::Migration[7.2]
  def change
    add_reference :payments, :order, null: true, foreign_key: true, index: true
  end
end
