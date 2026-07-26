# frozen_string_literal: true

require "rails_helper"

RSpec.describe "settled_on backfill" do
  let(:user) { create(:user) }
  let(:customer) { create(:customer, :with_credit) }

  def backfill!
    ActiveRecord::Base.connection.execute(<<~SQL)
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

  it "fills the collected date of fully paid orders from their last payment" do
    order = create(:order, :credit_order, customer: customer, user: user,
                   total_amount: 500, original_total_amount: 500)
    payment = create(:payment, customer: customer, amount: 500,
                     payment_date: Date.current - 3.days)
    create(:payment_allocation, payment: payment, order: order, amount: 500)
    order.update_column(:settled_on, nil)

    backfill!

    expect(order.reload.settled_on).to eq(Date.current - 3.days)
  end

  it "leaves partially paid orders alone" do
    order = create(:order, :credit_order, :pending, customer: customer, user: user,
                   total_amount: 500, original_total_amount: 500)
    payment = create(:payment, customer: customer, amount: 200)
    create(:payment_allocation, payment: payment, order: order, amount: 200)
    order.update_column(:settled_on, nil)

    backfill!

    expect(order.reload.settled_on).to be_nil
  end

  it "leaves cancelled orders alone" do
    order = create(:order, :credit_order, customer: customer, user: user,
                   total_amount: 500, original_total_amount: 500)
    payment = create(:payment, customer: customer, amount: 500)
    create(:payment_allocation, payment: payment, order: order, amount: 500)
    order.update_columns(settled_on: nil, status: "cancelled")

    backfill!

    expect(order.reload.settled_on).to be_nil
  end

  it "does not overwrite a date that is already set" do
    order = create(:order, :credit_order, customer: customer, user: user,
                   total_amount: 500, original_total_amount: 500)
    payment = create(:payment, customer: customer, amount: 500,
                     payment_date: Date.current)
    create(:payment_allocation, payment: payment, order: order, amount: 500)
    order.update_column(:settled_on, Date.current - 10.days)

    backfill!

    expect(order.reload.settled_on).to eq(Date.current - 10.days)
  end
end
