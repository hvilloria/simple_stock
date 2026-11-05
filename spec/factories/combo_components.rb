FactoryBot.define do
  factory :combo_component do
    association :combo, factory: [ :product, :combo ], components: []
    association :product
    quantity { 1 }
  end
end
