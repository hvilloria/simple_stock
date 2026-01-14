FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    password { "password123" }
    password_confirmation { "password123" }
    sequence(:name) { |n| "User #{n}" }
    role { "vendedor" }

    trait :vendedor do
      role { "vendedor" }
      sequence(:name) { |n| "Vendedor #{n}" }
    end

    trait :caja do
      role { "caja" }
      sequence(:name) { |n| "Caja #{n}" }
    end

    trait :admin do
      role { "admin" }
      sequence(:name) { |n| "Admin #{n}" }
    end
  end
end
