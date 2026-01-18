FactoryBot.define do
  factory :stock_movement do
    association :product
    association :stock_location
    quantity { 10 }
    movement_type { "purchase" }
    reference { nil }
    note { nil }

    trait :sale do
      quantity { -1 }
      movement_type { "sale" }
    end

    trait :adjustment do
      movement_type { "adjustment" }
    end

    trait :with_order_reference do
      association :reference, factory: :order
    end

    trait :with_purchase_reference do
      association :reference, factory: :purchase
    end
  end
end
