class AddCoveredAmountToPaymentAllocations < ActiveRecord::Migration[7.2]
  def change
    add_column :payment_allocations, :covered_amount, :decimal, precision: 10, scale: 2
  end
end
