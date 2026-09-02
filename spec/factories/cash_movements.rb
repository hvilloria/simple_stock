# frozen_string_literal: true

FactoryBot.define do
  factory :cash_movement do
    association :user, factory: [ :user, :caja ]
    business_date { Date.new(2026, 8, 3) }
    amount { 299_700 }
    category { "sale" }
    channel { "cash" }
    account { "drawer" }
    description { nil }

    trait :card_sale do
      channel { "card" }
      account { "bank" }
      amount { 54_700 }
    end

    trait :compensation_sale do
      channel { "compensation" }
      account { nil }
      amount { 661_188 }
    end

    trait :store_expense do
      category { "fixed_expense" }
      subcategory { "store_expenses" }
      channel { nil }
      account { "drawer" }
      amount { -13_000 }
      description { "Mundo de la Bolsa — 100 bolsas" }
    end

    trait :supplier_payment do
      category { "suppliers" }
      channel { nil }
      account { "bank" }
      amount { -153_951 }
      description { "Cromosol" }
    end

    trait :opening_balance do
      category { "opening_balance" }
      channel { nil }
      account { "main_cash" }
      amount { 12_497_899.30 }
      description { "Saldo inicial" }
    end

    trait :sealed do
      daily_closing { association :daily_closing, business_date: business_date }
    end
  end
end
