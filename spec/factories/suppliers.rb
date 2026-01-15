FactoryBot.define do
  factory :supplier do
    sequence(:name) { |n| "Supplier #{n}" }
    email { nil }
    phone { nil }
    cuit { nil }
    bank_alias { nil }
    bank_account { nil }
    payment_term_days { nil }

    trait :with_banking_info do
      bank_alias { "MI.ALIAS.CBU" }
      bank_account { "0170000040000012345678" }
    end

    trait :with_payment_terms do
      payment_term_days { 30 }
    end

    trait :japan do
      name { "JDM Auto Parts Japan" }
      email { "orders@jdmautoparts.jp" }
      phone { "+81-3-1234-5678" }
      payment_term_days { 30 }
    end

    trait :usa do
      name { "USA Honda Parts Wholesale" }
      email { "sales@usahondaparts.com" }
      phone { "+1-305-555-0199" }
      payment_term_days { 45 }
    end

    trait :germany do
      name { "Euro Auto Parts GmbH" }
      email { "info@euroautoparts.de" }
      phone { "+49-89-1234567" }
      payment_term_days { 15 }
    end

    trait :taiwan do
      name { "Taiwan Quality Auto Supply" }
      email { "export@twautosupply.tw" }
      phone { "+886-2-2345-6789" }
      payment_term_days { 30 }
    end

    trait :brazil do
      name { "Brasil Motor Parts Ltda" }
      email { "vendas@brasilmotorparts.com.br" }
      phone { "+55-11-3456-7890" }
      payment_term_days { 20 }
    end
  end
end
