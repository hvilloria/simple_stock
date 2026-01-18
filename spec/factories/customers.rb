FactoryBot.define do
  factory :customer do
    sequence(:name) { |n| "Customer #{n}" }
    document { "12345678" }
    phone { "+54 11 1234-5678" }
    has_credit_account { false }
    customer_type { "retail" }

    trait :with_credit do
      has_credit_account { true }
    end

    trait :workshop do
      customer_type { "workshop" }
      has_credit_account { true }
      sequence(:name) { |n| "Workshop #{n}" }
    end

    trait :mechanic do
      customer_type { "mechanic" }
      has_credit_account { true }
      sequence(:name) { |n| "Mechanic #{n}" }
    end

    trait :store do
      customer_type { "store" }
      has_credit_account { true }
      sequence(:name) { |n| "Store #{n}" }
    end
  end
end
