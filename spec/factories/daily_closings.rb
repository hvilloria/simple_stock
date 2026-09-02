# frozen_string_literal: true

FactoryBot.define do
  factory :daily_closing do
    association :user, factory: [ :user, :caja ]
    sequence(:business_date) { |n| Date.new(2026, 8, 1) + n.days }
    expected_cash { 311_700 }
    counted_cash { 311_700 }
    payway_batch_total { nil }
    mercado_pago_total { nil }
    closed_at { Time.current }

    trait :with_shortfall do
      counted_cash { 291_700 }
    end

    trait :fully_verified do
      payway_batch_total { 109_020 }
      mercado_pago_total { 77_200 }
    end
  end
end
