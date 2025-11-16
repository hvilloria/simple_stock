class Order < ApplicationRecord
  belongs_to :customer, optional: true
  has_many :order_items, dependent: :destroy

  enum :status, {
    confirmed: "confirmed",
    cancelled: "cancelled"
  }, suffix: true

  def calculate_total!
    update!(total_amount: order_items.sum("quantity * unit_price"))
  end

  def cancel!(reason: nil)
    Sales::CancelOrder.call(order: self, reason: reason)
  end
end
