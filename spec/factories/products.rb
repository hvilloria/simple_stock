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

    # Traits por categoría
    trait :frenos do
      category { "frenos" }
    end

    trait :motor do
      category { "motor" }
    end

    trait :suspension do
      category { "suspension" }
    end

    trait :transmision do
      category { "transmision" }
    end

    trait :electrico do
      category { "electrico" }
    end

    trait :carroceria do
      category { "carroceria" }
    end

    trait :filtros do
      category { "filtros" }
    end

    trait :lubricantes do
      category { "lubricantes" }
    end

    # Traits por origen aftermarket
    trait :aftermarket_germany do
      product_type { "aftermarket" }
      origin { "germany" }
      brand { ["Bosch", "TRW", "Mann Filter", "Sachs"].sample }
    end

    trait :aftermarket_korea do
      product_type { "aftermarket" }
      origin { "korea" }
      brand { ["Mobis", "Mando", "CTR"].sample }
    end

    trait :aftermarket_brazil do
      product_type { "aftermarket" }
      origin { "brazil" }
      brand { ["Cofap", "Nakata", "TRW Brasil"].sample }
    end

    trait :aftermarket_india do
      product_type { "aftermarket" }
      origin { "india" }
      brand { ["Gabriel", "Rane", "Bosch India"].sample }
    end

    trait :aftermarket_taiwan do
      product_type { "aftermarket" }
      origin { "taiwan" }
      brand { ["TYC", "Depo", "Taiwan Golden Bee"].sample }
    end

    trait :oem_usa do
      product_type { "oem" }
      origin { "usa" }
      brand { "Honda" }
    end

    trait :oem_japan do
      product_type { "oem" }
      origin { "japan" }
      brand { "Honda" }
    end

    # Trait para productos Honda realistas
    trait :honda_part do
      brand { "Honda" }
      cost_currency { "USD" }
    end
  end
end
