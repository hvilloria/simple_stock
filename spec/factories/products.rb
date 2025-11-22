FactoryBot.define do
  factory :product do
    sequence(:name) { |n| "Product #{n}" }
    sequence(:sku) { |n| "SKU#{n.to_s.rjust(6, '0')}" }
    category { "frenos" }
    cost_unit { 50.0 }
    price_unit { 100.0 }
    current_stock { 10 }
    active { true }
    cost_currency { "ARS" }
    brand { "Generic Brand" }
    origin { nil }
    product_type { nil }

    trait :inactive do
      active { false }
    end

    trait :low_stock do
      current_stock { 3 }
    end

    trait :cost_in_usd do
      cost_currency { "USD" }
      cost_unit { 50 }
    end

    trait :cost_in_ars do
      cost_currency { "ARS" }
      cost_unit { 60000 }
    end

    trait :oem do
      product_type { "oem" }
      origin { "japan" }
    end

    trait :aftermarket_japan do
      product_type { "aftermarket" }
      origin { "japan" }
    end

    trait :aftermarket_china do
      product_type { "aftermarket" }
      origin { "china" }
    end
  end
end
