FactoryBot.define do
  factory :order do
    customer { Customer.mostrador }
    status { "confirmed" }
    order_type { "cash" }
    total_amount { 100.0 }
    channel { nil }
    source { "live" }
    sale_date { Date.today }

    trait :credit_order do
      order_type { "credit" }
      association :customer, factory: [ :customer, :with_credit ]
    end

    trait :cancelled do
      status { "cancelled" }
    end

    trait :with_counter_channel do
      channel { "counter" }
    end

    trait :with_whatsapp_channel do
      channel { "whatsapp" }
    end

    trait :with_mercadolibre_channel do
      channel { "mercadolibre" }
    end

    trait :from_paper do
      source { "from_paper" }
      paper_number { "0001" }
      total_amount { 0 }
      sale_date { Date.today }
    end

    trait :live do
      source { "live" }
      sale_date { Date.today }
    end
  end
end
