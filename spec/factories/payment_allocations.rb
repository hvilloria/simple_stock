# frozen_string_literal: true

FactoryBot.define do
  factory :payment_allocation do
    payment
    order
    amount { 100.0 }
  end
end
