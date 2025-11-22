FactoryBot.define do
  factory :supplier do
    sequence(:name) { |n| "Supplier #{n}" }
    contact_name { nil }
    phone { nil }
    email { nil }
    address { nil }
    notes { nil }

    trait :with_contact do
      contact_name { "John Doe" }
      phone { "+1 555-1234" }
    end

    trait :with_email do
      email { "supplier@example.com" }
    end
  end
end
