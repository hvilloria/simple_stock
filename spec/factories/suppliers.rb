FactoryBot.define do
  factory :supplier do
    sequence(:name) { |n| "Supplier #{n}" }
    contact_name { nil }
    phone { nil }
    email { nil }
    address { nil }
    notes { nil }

    trait :with_contact do
      contact_name { "John Doe" }
      phone { "+1 555-1234" }
    end

    trait :with_email do
      email { "supplier@example.com" }
    end

    trait :japan do
      name { "JDM Auto Parts Japan" }
      contact_name { "Takeshi Yamamoto" }
      email { "orders@jdmautoparts.jp" }
      phone { "+81-3-1234-5678" }
      address { "1-2-3 Shibuya, Tokyo 150-0002, Japan" }
      notes { "Proveedor de partes OEM originales Honda de Japón" }
    end

    trait :usa do
      name { "USA Honda Parts Wholesale" }
      contact_name { "Michael Johnson" }
      email { "sales@usahondaparts.com" }
      phone { "+1-305-555-0199" }
      address { "1250 NW 79th Ave, Miami, FL 33126, USA" }
      notes { "Distribuidor oficial de partes Honda en USA" }
    end

    trait :germany do
      name { "Euro Auto Parts GmbH" }
      contact_name { "Hans Mueller" }
      email { "info@euroautoparts.de" }
      phone { "+49-89-1234567" }
      address { "Industriestraße 45, 80939 Munich, Germany" }
      notes { "Partes aftermarket premium alemanas - Bosch, TRW" }
    end

    trait :taiwan do
      name { "Taiwan Quality Auto Supply" }
      contact_name { "Chen Wei" }
      email { "export@twautosupply.tw" }
      phone { "+886-2-2345-6789" }
      address { "No. 123, Section 2, Taipei, Taiwan" }
      notes { "Partes aftermarket de calidad intermedia" }
    end

    trait :brazil do
      name { "Brasil Motor Parts Ltda" }
      contact_name { "Carlos Silva" }
      email { "vendas@brasilmotorparts.com.br" }
      phone { "+55-11-3456-7890" }
      address { "Rua das Indústrias 456, São Paulo, SP, Brazil" }
      notes { "Distribuidor de partes aftermarket para Latinoamérica" }
    end
  end
end
