FactoryBot.define do
  factory :sales_ledger_sales_import, class: "SalesLedger::SalesImport" do
    source_filename { "test.csv" }
    status { "completed" }
    imported_at { Time.current }
    rows_count { 0 }
    created_products_count { 0 }
    created_entries_count { 0 }
    failed_rows_count { 0 }
  end
end
