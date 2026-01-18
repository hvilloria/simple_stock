FactoryBot.define do
  factory :stock_location do
    sequence(:name) { |n| "Location #{n}" }
    sequence(:code) { |n| "LOC#{n.to_s.rjust(3, '0')}" }
    address { "123 Main St" }
  end
end
