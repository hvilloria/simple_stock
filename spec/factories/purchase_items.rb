FactoryBot.define do
  factory :purchase_item do
    association :purchase
    association :product
    quantity { 10 }
    unit_cost { 50.0 }
  end
end
