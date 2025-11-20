FactoryBot.define do
  factory :order do
    association :customer
    status { "confirmed" }
    order_type { "cash" }
    total_amount { 0 }

    trait :credit do
      order_type { "credit" }
    end

    trait :cancelled do
      status { "cancelled" }
    end
  end
end

