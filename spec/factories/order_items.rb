FactoryBot.define do
  factory :order_item do
    association :order
    association :product
    quantity { 1 }
    unit_price { 100.0 }
  end
end

