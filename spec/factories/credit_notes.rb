FactoryBot.define do
  factory :credit_note do
    association :supplier
    sequence(:credit_note_number) { |n| "NC-#{n.to_s.rjust(3, '0')}" }
    amount { 1000.0 }
    currency { "ARS" }
    exchange_rate { nil }
    issue_date { Date.today }
    notes { nil }

    trait :with_invoice do
      association :invoice
      after(:build) do |credit_note|
        credit_note.currency = credit_note.invoice.currency
        credit_note.exchange_rate = credit_note.invoice.exchange_rate
      end
    end

    trait :usd do
      currency { "USD" }
      exchange_rate { 1200.0 }
    end

    trait :ars do
      currency { "ARS" }
      exchange_rate { nil }
    end
  end
end
