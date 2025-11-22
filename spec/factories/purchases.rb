FactoryBot.define do
  factory :purchase do
    association :supplier
    currency { "USD" }
    exchange_rate { 1200 }
    purchase_date { Date.today }
    status { "confirmed" }
    total_cost { nil }
    notes { nil }

    trait :in_ars do
      currency { "ARS" }
      exchange_rate { nil }
    end

    trait :cancelled do
      status { "cancelled" }
    end
  end
end
