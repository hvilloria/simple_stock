# frozen_string_literal: true

FactoryBot.define do
  factory :voided_payment_allocation do
    payment
    order
    amount { 100.0 }
  end
end
