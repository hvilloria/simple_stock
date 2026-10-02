# frozen_string_literal: true

class AddDiscountAmountToPaymentAllocations < ActiveRecord::Migration[7.2]
  def change
    add_column :payment_allocations, :discount_amount, :decimal, precision: 10, scale: 2, default: 0, null: false
  end
end
