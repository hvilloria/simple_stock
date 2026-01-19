FactoryBot.define do
  factory :credit_note_item do
    association :credit_note
    association :product
    quantity { 1 }
    unit_price { 100.0 }
  end
end
