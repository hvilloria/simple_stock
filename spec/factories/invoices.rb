FactoryBot.define do
  factory :invoice do
    association :supplier
    currency { "USD" }
    exchange_rate { 1200 }
    purchase_date { Date.today }
    status { "confirmed" }
    total_cost { nil }
    notes { nil }
    has_items { true }

    # Por defecto crea en full mode para compatibilidad con tests existentes
    after(:build) do |invoice, evaluator|
      if invoice.has_items? && invoice.invoice_items.empty?
        invoice.invoice_items.build(
          product: create(:product),
          quantity: 10,
          unit_cost: 50
        )
      end
    end

    trait :in_ars do
      currency { "ARS" }
      exchange_rate { nil }
    end

    trait :cancelled do
      status { "cancelled" }
    end

    trait :simple_mode do
      invoice_number { "FAC-#{rand(1000..9999)}" }
      amount { rand(1000..10000) }
      due_date { 30.days.from_now }
      status { "pending" }
      has_items { false }

      after(:build) do |invoice|
        # Limpiar invoice_items para simple mode
        invoice.invoice_items.clear
      end
    end

    trait :full_mode do
      has_items { true }
      status { "confirmed" }
    end

    trait :overdue do
      simple_mode
      status { "pending" }
      due_date { 1.week.ago }
    end

    trait :paid do
      simple_mode
      status { "paid" }
      paid_at { Date.yesterday }
    end
  end
end
