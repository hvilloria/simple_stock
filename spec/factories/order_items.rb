FactoryBot.define do
  factory :order_item do
    association :order
    association :product
    quantity { 1 }
    unit_price { 100.0 }

    trait :delivered do
      delivered_at { Time.current }
    end
  end
end
