FactoryBot.define do
  factory :sales_ledger_entry, class: "SalesLedger::Entry" do
    association :sales_import, factory: :sales_ledger_sales_import
    association :product
    sale_date             { Date.current }
    ticket_number         { "T-001" }
    oem_code              { "12345" }
    product_name_snapshot { "Oil Filter" }
    quantity              { 2 }
    unit_price            { BigDecimal("1500") }
    total_amount          { BigDecimal("3000") }
    entry_fingerprint     { SecureRandom.hex(32) }
    raw_row_data          { {} }
  end
end
