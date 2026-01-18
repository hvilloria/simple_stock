# frozen_string_literal: true

FactoryBot.define do
  factory :payment do
    association :customer, factory: [ :customer, :with_credit ]
    amount { 10000.0 }
    payment_method { "cash" }
    payment_date { Date.today }
    notes { nil }

    trait :transfer do
      payment_method { "transfer" }
      notes { "Transfer reference #123456" }
    end

    trait :check do
      payment_method { "check" }
      notes { "Check #789" }
    end

    trait :card do
      payment_method { "card" }
      notes { "Card payment" }
    end
  end
end
