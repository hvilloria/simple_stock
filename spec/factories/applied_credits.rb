FactoryBot.define do
  factory :applied_credit do
    association :credit_note
    association :invoice
    amount { 500.0 }
    applied_at { Date.today }
  end
end
