# frozen_string_literal: true

FactoryBot.define do
  factory :payment do
    association :customer, factory: [ :customer, :with_credit ]
    amount { 10000.0 }
    payment_method { "cash" }
    payment_date { Date.current }
    notes { nil }

    trait :bank_qr do
      payment_method { "bank_qr" }
      notes { "Banco QR" }
    end

    trait :bank_card do
      payment_method { "bank_card" }
      notes { "Banco Tarjeta" }
    end

    trait :bank_transfer do
      payment_method { "bank_transfer" }
      notes { "Banco Transferencia" }
    end

    trait :mercado_pago do
      payment_method { "mercado_pago" }
      notes { "Mercado Pago" }
    end
  end
end
