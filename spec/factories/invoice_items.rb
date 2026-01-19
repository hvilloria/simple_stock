FactoryBot.define do
  factory :invoice_item do
    association :invoice
    association :product
    quantity { 10 }
    unit_cost { 50.0 }
  end
end
