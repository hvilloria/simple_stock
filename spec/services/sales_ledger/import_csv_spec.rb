# frozen_string_literal: true

require "rails_helper"
require "csv"

RSpec.describe SalesLedger::ImportCsv do
  IMPORT_CSV_SPEC_HEADERS = %w[
    sale_date ticket_number oem_code product_name quantity unit_price
    ticket_total_amount payment_method seller_name
  ].freeze

  # Builds a Tempfile with real CSV content using the stdlib CSV library.
  # The caller is responsible for closing and unlinking the file.
  def build_csv(rows, headers: IMPORT_CSV_SPEC_HEADERS)
    tmp = Tempfile.new([ "import_csv_spec", ".csv" ])
    content = CSV.generate do |csv|
      csv << headers
      rows.each { |r| csv << r }
    end
    tmp.write(content)
    tmp.rewind
    tmp
  end

  # Safe Tempfile management: register files here and the after block cleans them up
  let(:tempfiles) { [] }
  after { tempfiles.each { |f| f.close; f.unlink rescue nil } }

  def build_csv_tracked(*args, **kwargs)
    tmp = build_csv(*args, **kwargs)
    tempfiles << tmp
    tmp
  end

  describe ".call" do
    # ── CASE 1: Successful import ────────────────────────────────────────────
    # Row format: [sale_date, ticket_number, oem_code, product_name, quantity,
    #              unit_price, ticket_total_amount, payment_method, seller_name]
    context "with a valid two-row CSV" do
      let(:csv) do
        build_csv_tracked([
          # T-001: two items, total 3000 + 3200 = 6200
          [ "2024-01-15", "T-001", "12345", "Oil Filter", "2", "1500.00", "6200.00", "cash", "Juan" ],
          [ "2024-01-15", "T-001", "67890", "NGK Spark",  "4",  "800.00", "6200.00", "cash", "Juan" ]
        ])
      end

      subject(:result) { described_class.call(file: csv, filename: "sales.csv") }

      it "returns Result.success? = true" do
        expect(result.success?).to be true
      end

      it "creates a SalesImport with status 'completed'" do
        expect(result.record).to be_a(SalesLedger::SalesImport)
        expect(result.record.status).to eq("completed")
      end

      it "creates exactly 2 entries" do
        expect { result }.to change(SalesLedger::Entry, :count).by(2)
      end

      it "records correct metrics on the SalesImport" do
        import = result.record
        expect(import.rows_count).to eq(2)
        expect(import.created_entries_count).to eq(2)
        expect(import.failed_rows_count).to eq(0)
      end

      it "calculates total_amount as quantity * unit_price" do
        result
        entry = SalesLedger::Entry.find_by(oem_code: "12345")
        expect(entry.total_amount).to eq(BigDecimal("3000.00"))
      end

      it "stores payment_method, seller_name, and ticket_total_amount on the entry" do
        result
        entry = SalesLedger::Entry.find_by(oem_code: "12345")
        expect(entry.payment_method).to eq("cash")
        expect(entry.seller_name).to eq("Juan")
        expect(entry.ticket_total_amount).to eq(BigDecimal("6200.00"))
      end

      it "associates each entry with the created SalesImport" do
        import = result.record
        import.entries.each do |entry|
          expect(entry.sales_import).to eq(import)
        end
      end

      it "associates each entry with a non-nil Product" do
        result
        SalesLedger::Entry.last(2).each do |entry|
          expect(entry.product).to be_a(Product)
        end
      end
    end

    # ── CASE 2: Auto-creation of products ────────────────────────────────────
    context "when the product does not exist in the database" do
      let(:csv) do
        build_csv_tracked([ [ "2024-01-15", "T-001", "NEW-SKU", "Brand New Part", "1", "500.00", "500.00", "cash", "Juan" ] ])
      end

      it "creates a new Product" do
        expect {
          described_class.call(file: csv, filename: "sales.csv")
        }.to change(Product, :count).by(1)
      end

      it "sets sku, name, price_unit, active: true with nil brand and origin" do
        described_class.call(file: csv, filename: "sales.csv")
        product = Product.find_by(sku: "NEW-SKU")
        expect(product).to have_attributes(
          sku:        "NEW-SKU",
          name:       "Brand New Part",
          price_unit: BigDecimal("500.00"),
          active:     true,
          brand:      nil,
          origin:     nil
        )
      end

      it "records created_products_count = 1 on the import" do
        result = described_class.call(file: csv, filename: "sales.csv")
        expect(result.record.created_products_count).to eq(1)
      end
    end

    # ── CASE 3: product_type inference from oem_code ──────────────────────────
    context "product_type inference from oem_code" do
      it "assigns 'oem' when the code does not end in -IM or -IMP" do
        csv = build_csv_tracked([ [ "2024-01-15", "T-001", "12345", "OEM Part", "1", "100", "100.00", "cash", "Juan" ] ])
        described_class.call(file: csv, filename: "sales.csv")
        expect(Product.find_by(sku: "12345").product_type).to eq("oem")
      end

      it "assigns 'aftermarket' when the code ends in -IM, storing normalized sku without suffix" do
        csv = build_csv_tracked([ [ "2024-01-15", "T-001", "12345-IM", "After Part", "1", "100", "100.00", "cash", "Juan" ] ])
        described_class.call(file: csv, filename: "sales.csv")
        product = Product.find_by(sku: "12345", product_type: "aftermarket")
        expect(product).to be_present
        expect(Product.find_by(sku: "12345-IM")).to be_nil
      end

      it "assigns 'aftermarket' when the code ends in -IMP, storing normalized sku without suffix" do
        csv = build_csv_tracked([ [ "2024-01-15", "T-001", "12345-IMP", "After Part", "1", "100", "100.00", "cash", "Juan" ] ])
        described_class.call(file: csv, filename: "sales.csv")
        product = Product.find_by(sku: "12345", product_type: "aftermarket")
        expect(product).to be_present
        expect(Product.find_by(sku: "12345-IMP")).to be_nil
      end

      it "normalizes oem_code to upcase and strips suffix for product sku; entry keeps original" do
        csv = build_csv_tracked([ [ "2024-01-15", "T-001", "abc-im", "Part", "1", "100", "100.00", "cash", "Juan" ] ])
        described_class.call(file: csv, filename: "sales.csv")
        entry = SalesLedger::Entry.last
        expect(entry.oem_code).to eq("ABC-IM")           # original preserved in entry
        expect(Product.find_by(sku: "ABC")).to be_present # normalized sku on product
        expect(Product.find_by(sku: "ABC-IM")).to be_nil  # suffix not stored on product
      end

      it "strips leading/trailing spaces and upcases oem_code, then strips suffix for product sku" do
        csv = build_csv_tracked([ [ "2024-01-15", "T-001", "  abc-im  ", "Part", "1", "100", "100.00", "cash", "Juan" ] ])
        described_class.call(file: csv, filename: "sales.csv")
        entry = SalesLedger::Entry.last
        expect(entry.oem_code).to eq("ABC-IM")           # stripped+upcased original
        expect(Product.find_by(sku: "ABC")).to be_present # suffix stripped from product sku
      end

      # Mixed batch: "NORMAL-IM" and "NORMAL-IMP" both normalize to sku="NORMAL" + aftermarket.
      # The second row reuses the product created by the first → 2 products, 3 entries.
      context "with OEM, -IM, and -IMP codes in the same batch" do
        let(:csv) do
          build_csv_tracked([
            [ "2024-01-15", "T-001", "NORMAL",     "OEM Part",        "1", "100", "100.00", "cash", "Juan" ],
            [ "2024-01-15", "T-002", "NORMAL-IM",  "Aftermarket IM",  "1", "100", "100.00", "cash", "Juan" ],
            [ "2024-01-15", "T-003", "NORMAL-IMP", "Aftermarket IMP", "1", "100", "100.00", "cash", "Juan" ]
          ])
        end

        it "creates one oem product and one aftermarket product for the shared base sku" do
          described_class.call(file: csv, filename: "sales.csv")
          expect(Product.find_by(sku: "NORMAL", product_type: "oem")).to be_present
          expect(Product.find_by(sku: "NORMAL", product_type: "aftermarket")).to be_present
          expect(Product.where(sku: "NORMAL").count).to eq(2)
        end

        it "creates 2 products and 3 entries (-IM and -IMP share the aftermarket product)" do
          expect {
            described_class.call(file: csv, filename: "sales.csv")
          }.to change(Product, :count).by(2).and change(SalesLedger::Entry, :count).by(3)
        end
      end
    end

    # ── CASE 4: Reuse of existing product ────────────────────────────────────
    # Service lookup: find_by(sku: upcased_oem_code, product_type: inferred_type)
    # "EXIST-001" has no -IM/-IMP suffix → inferred product_type is "oem"
    context "when a product with the same sku and inferred product_type already exists" do
      let!(:existing_product) do
        create(:product,
               sku:          "EXIST-001",
               product_type: "oem",
               name:         "Original Name",
               price_unit:   999)
      end

      let(:csv) do
        build_csv_tracked([ [ "2024-01-15", "T-001", "EXIST-001", "Name from CSV", "3", "1200.00", "3600.00", "cash", "Juan" ] ])
      end

      it "does not create a new product" do
        expect {
          described_class.call(file: csv, filename: "sales.csv")
        }.not_to change(Product, :count)
      end

      it "does not modify the name or price of the existing product" do
        described_class.call(file: csv, filename: "sales.csv")
        existing_product.reload
        expect(existing_product.name).to eq("Original Name")
        expect(existing_product.price_unit).to eq(BigDecimal("999"))
      end

      it "associates the created entry with the existing product" do
        described_class.call(file: csv, filename: "sales.csv")
        entry = SalesLedger::Entry.find_by(oem_code: "EXIST-001")
        expect(entry.product).to eq(existing_product)
      end

      it "records created_products_count = 0 on the import" do
        result = described_class.call(file: csv, filename: "sales.csv")
        expect(result.record.created_products_count).to eq(0)
      end
    end

    # ── CASE 5: Fingerprint deduplication ────────────────────────────────────
    # Duplicates increment @skipped_count, which does NOT count toward failed_rows_count
    context "when the same CSV is imported again" do
      let(:rows) do
        [ [ "2024-01-15", "T-001", "12345", "Oil Filter", "2", "1500.00", "3000.00", "cash", "Juan" ] ]
      end

      it "does not create duplicate entries on the second import" do
        csv1 = build_csv_tracked(rows)
        described_class.call(file: csv1, filename: "sales.csv")

        csv2 = build_csv_tracked(rows)
        expect {
          described_class.call(file: csv2, filename: "sales.csv")
        }.not_to change(SalesLedger::Entry, :count)
      end

      it "the second import completes successfully" do
        csv1 = build_csv_tracked(rows)
        described_class.call(file: csv1, filename: "sales.csv")

        csv2 = build_csv_tracked(rows)
        result = described_class.call(file: csv2, filename: "sales.csv")
        expect(result.success?).to be true
        expect(result.record.status).to eq("completed")
      end

      it "records metrics consistent with the silent skip" do
        csv1 = build_csv_tracked(rows)
        described_class.call(file: csv1, filename: "sales.csv")

        csv2 = build_csv_tracked(rows)
        result = described_class.call(file: csv2, filename: "sales.csv")
        import = result.record
        # The row was counted (rows_count = 1) but generated no entry or failure
        expect(import.rows_count).to eq(1)
        expect(import.created_entries_count).to eq(0)
        expect(import.failed_rows_count).to eq(0)  # duplicates are not failures
      end
    end

    # ── CASE 6: Missing required headers ─────────────────────────────────────
    # Header validation fires in process_csv before any rows are processed.
    # The raise propagates to call's rescue → status: "failed"
    context "when required columns are missing from the CSV" do
      let(:csv_missing_product_name) do
        build_csv_tracked(
          [ [ "2024-01-15", "T-001", "12345", "2", "1500.00", "3000.00", "cash", "Juan" ] ],
          headers: %w[sale_date ticket_number oem_code quantity unit_price ticket_total_amount payment_method seller_name]
        )
      end

      it "returns Result.success? = false" do
        result = described_class.call(file: csv_missing_product_name, filename: "sales.csv")
        expect(result.success?).to be false
      end

      it "sets the SalesImport status to 'failed'" do
        result = described_class.call(file: csv_missing_product_name, filename: "sales.csv")
        expect(result.record.status).to eq("failed")
      end

      it "does not create any entries" do
        expect {
          described_class.call(file: csv_missing_product_name, filename: "sales.csv")
        }.not_to change(SalesLedger::Entry, :count)
      end

      it "does not create any products" do
        expect {
          described_class.call(file: csv_missing_product_name, filename: "sales.csv")
        }.not_to change(Product, :count)
      end

      it "includes the missing column name in Result.errors" do
        result = described_class.call(file: csv_missing_product_name, filename: "sales.csv")
        expect(result.errors).not_to be_empty
        expect(result.errors.first).to include("product_name")
      end

      it "returns failure when ticket_total_amount column is missing" do
        csv = build_csv_tracked(
          [ [ "2024-01-15", "T-001", "12345", "Filter", "2", "1500.00", "cash", "Juan" ] ],
          headers: %w[sale_date ticket_number oem_code product_name quantity unit_price payment_method seller_name]
        )
        result = described_class.call(file: csv, filename: "sales.csv")
        expect(result.success?).to be false
        expect(result.errors.first).to include("ticket_total_amount")
      end

      it "returns failure when seller_name column is missing" do
        csv = build_csv_tracked(
          [ [ "2024-01-15", "T-001", "12345", "Filter", "2", "1500.00", "3000.00", "cash" ] ],
          headers: %w[sale_date ticket_number oem_code product_name quantity unit_price ticket_total_amount payment_method]
        )
        result = described_class.call(file: csv, filename: "sales.csv")
        expect(result.success?).to be false
        expect(result.errors.first).to include("seller_name")
      end
    end

    # ── CASE 7: Invalid rows (row-level errors) ───────────────────────────────
    # Each row error is rescued individually → @failed_rows.
    # The import proceeds and ends with status "completed".
    context "with rows containing invalid data" do
      context "when quantity is 0" do
        let(:csv) do
          build_csv_tracked([
            [ "2024-01-15", "T-001", "12345", "Filter", "0",  "1500.00", "3000.00", "cash", "Juan" ],  # invalid
            [ "2024-01-15", "T-002", "67890", "Spark",  "2",   "800.00", "1600.00", "cash", "Juan" ]   # valid
          ])
        end

        subject(:result) { described_class.call(file: csv, filename: "sales.csv") }

        it "processes the valid row and skips the invalid one" do
          expect { result }.to change(SalesLedger::Entry, :count).by(1)
        end

        it "the import status is 'completed' and result is successful" do
          expect(result.record.status).to eq("completed")
          expect(result.success?).to be true
        end

        it "records failed_rows_count = 1 and created_entries_count = 1" do
          expect(result.record.failed_rows_count).to eq(1)
          expect(result.record.created_entries_count).to eq(1)
        end
      end

      context "when unit_price is blank" do
        let(:csv) do
          build_csv_tracked([
            [ "2024-01-15", "T-001", "12345", "Filter", "2", "",        "3000.00", "cash", "Juan" ],  # invalid
            [ "2024-01-15", "T-002", "67890", "Spark",  "3", "800.00",  "2400.00", "cash", "Juan" ]   # valid
          ])
        end

        it "skips the blank-price row and processes the valid one" do
          result = described_class.call(file: csv, filename: "sales.csv")
          expect(result.record.created_entries_count).to eq(1)
          expect(result.record.failed_rows_count).to eq(1)
        end
      end

      context "when ticket_number is blank" do
        let(:csv) do
          build_csv_tracked([ [ "2024-01-15", "", "12345", "Filter", "2", "1500.00", "3000.00", "cash", "Juan" ] ])
        end

        it "discards the row and completes the import with 0 entries and 1 failed row" do
          result = described_class.call(file: csv, filename: "sales.csv")
          expect(result.record.status).to eq("completed")
          expect(result.record.created_entries_count).to eq(0)
          expect(result.record.failed_rows_count).to eq(1)
        end
      end

      context "when sale_date has an invalid format (e.g. 'bad-date')" do
        let(:csv) do
          build_csv_tracked([ [ "bad-date", "T-001", "12345", "Filter", "2", "1500.00", "3000.00", "cash", "Juan" ] ])
        end

        it "discards the row and records failed_rows_count = 1" do
          result = described_class.call(file: csv, filename: "sales.csv")
          expect(result.record.failed_rows_count).to eq(1)
          expect(result.record.created_entries_count).to eq(0)
        end

        it "mentions accepted formats in the error (visible in import notes)" do
          result = described_class.call(file: csv, filename: "sales.csv")
          expect(result.record.notes).to include("YYYY-MM-DD")
          expect(result.record.notes).to include("M/D/YYYY")
        end
      end

      context "when sale_date comes from Google Sheets (M/D/YYYY or M/D/YY)" do
        it "accepts M/D/YYYY format and parses it correctly" do
          csv = build_csv_tracked([ [ "3/28/2026", "T-001", "12345", "Filter", "2", "1500.00", "3000.00", "cash", "Juan" ] ])
          result = described_class.call(file: csv, filename: "sales.csv")
          expect(result.record.created_entries_count).to eq(1)
          expect(SalesLedger::Entry.last.sale_date).to eq(Date.new(2026, 3, 28))
        end

        it "accepts M/D/YY format and parses it correctly" do
          csv = build_csv_tracked([ [ "3/28/26", "T-001", "12345", "Filter", "2", "1500.00", "3000.00", "cash", "Juan" ] ])
          result = described_class.call(file: csv, filename: "sales.csv")
          expect(result.record.created_entries_count).to eq(1)
          expect(SalesLedger::Entry.last.sale_date).to eq(Date.new(2026, 3, 28))
        end

        it "still accepts the canonical YYYY-MM-DD format" do
          csv = build_csv_tracked([ [ "2026-03-28", "T-001", "12345", "Filter", "2", "1500.00", "3000.00", "cash", "Juan" ] ])
          result = described_class.call(file: csv, filename: "sales.csv")
          expect(result.record.created_entries_count).to eq(1)
          expect(SalesLedger::Entry.last.sale_date).to eq(Date.new(2026, 3, 28))
        end

        it "rejects an ambiguous or unknown format (e.g. 28-03-2026)" do
          csv = build_csv_tracked([ [ "28-03-2026", "T-001", "12345", "Filter", "2", "1500.00", "3000.00", "cash", "Juan" ] ])
          result = described_class.call(file: csv, filename: "sales.csv")
          expect(result.record.failed_rows_count).to eq(1)
          expect(result.record.created_entries_count).to eq(0)
        end
      end

      context "when payment_method is not a valid value" do
        let(:csv) do
          build_csv_tracked([
            [ "2024-01-15", "T-001", "12345", "Filter", "2", "1500.00", "3000.00", "efectivo", "Juan" ],  # invalid
            [ "2024-01-15", "T-002", "67890", "Spark",  "2",  "800.00", "1600.00", "cash",     "Juan" ]   # valid
          ])
        end

        it "skips the row with invalid payment_method and processes the valid one" do
          result = described_class.call(file: csv, filename: "sales.csv")
          expect(result.record.created_entries_count).to eq(1)
          expect(result.record.failed_rows_count).to eq(1)
        end
      end

      context "when payment_method is blank" do
        let(:csv) do
          build_csv_tracked([ [ "2024-01-15", "T-001", "12345", "Filter", "2", "1500.00", "3000.00", "", "Juan" ] ])
        end

        it "discards the row and records failed_rows_count = 1" do
          result = described_class.call(file: csv, filename: "sales.csv")
          expect(result.record.failed_rows_count).to eq(1)
          expect(result.record.created_entries_count).to eq(0)
        end
      end

      context "when payment_method is provided in mixed case" do
        let(:csv) do
          build_csv_tracked([ [ "2024-01-15", "T-001", "12345", "Filter", "2", "1500.00", "3000.00", "Cash", "Juan" ] ])
        end

        it "normalizes payment_method to downcase and imports the row successfully" do
          result = described_class.call(file: csv, filename: "sales.csv")
          expect(result.success?).to be true
          expect(SalesLedger::Entry.find_by(ticket_number: "T-001").payment_method).to eq("cash")
        end
      end

      context "when seller_name is blank" do
        let(:csv) do
          build_csv_tracked([ [ "2024-01-15", "T-001", "12345", "Filter", "2", "1500.00", "3000.00", "cash", "" ] ])
        end

        it "discards the row and records failed_rows_count = 1" do
          result = described_class.call(file: csv, filename: "sales.csv")
          expect(result.record.failed_rows_count).to eq(1)
          expect(result.record.created_entries_count).to eq(0)
        end
      end

      context "when ticket_total_amount is not numeric" do
        let(:csv) do
          build_csv_tracked([ [ "2024-01-15", "T-001", "12345", "Filter", "2", "1500.00", "abc", "cash", "Juan" ] ])
        end

        it "discards the row and records failed_rows_count = 1" do
          result = described_class.call(file: csv, filename: "sales.csv")
          expect(result.record.failed_rows_count).to eq(1)
          expect(result.record.created_entries_count).to eq(0)
        end
      end
    end

    # ── CASE 8: Result structure ──────────────────────────────────────────────
    context "Result structure" do
      context "on success" do
        let(:csv) do
          build_csv_tracked([ [ "2024-01-15", "T-001", "12345", "Filter", "2", "1500.00", "3000.00", "cash", "Juan" ] ])
        end

        subject(:result) { described_class.call(file: csv, filename: "sales.csv") }

        it "Result.record is a persisted SalesLedger::SalesImport" do
          expect(result.record).to be_a(SalesLedger::SalesImport)
          expect(result.record).to be_persisted
        end

        it "Result.errors is an empty Array" do
          expect(result.errors).to be_an(Array)
          expect(result.errors).to be_empty
        end
      end

      context "on a fatal error (missing header)" do
        let(:csv) do
          build_csv_tracked(
            [ [ "2024-01-15", "T-001", "12345", "2", "1500.00", "3000.00", "cash", "Juan" ] ],
            headers: %w[sale_date ticket_number oem_code quantity unit_price ticket_total_amount payment_method seller_name]
          )
        end

        subject(:result) { described_class.call(file: csv, filename: "sales.csv") }

        it "Result.success? is false" do
          expect(result.success?).to be false
        end

        it "Result.record is a persisted instance with status 'failed'" do
          expect(result.record).to be_a(SalesLedger::SalesImport)
          expect(result.record).to be_persisted
          expect(result.record.status).to eq("failed")
        end

        it "Result.errors is a non-empty Array" do
          expect(result.errors).to be_an(Array)
          expect(result.errors).not_to be_empty
        end
      end
    end

    # ── CASE 9: Ticket field consistency validation ───────────────────────────
    # When rows of the same ticket have inconsistent values for payment_method,
    # seller_name, sale_date, or ticket_total_amount, the entire ticket is rejected.
    # Other tickets in the same import are not affected.
    context "ticket field consistency validation" do
      it "rejects all rows of a ticket when payment_method differs between rows" do
        csv = build_csv_tracked([
          [ "2024-01-15", "T-001", "AAA", "Part A", "1", "100.00", "200.00", "cash", "Juan" ],
          [ "2024-01-15", "T-001", "BBB", "Part B", "1", "100.00", "200.00", "bank", "Juan" ],  # different payment_method
          [ "2024-01-15", "T-002", "CCC", "Part C", "1", "500.00", "500.00", "cash", "Juan" ]   # valid separate ticket
        ])
        result = described_class.call(file: csv, filename: "sales.csv")
        expect(result.success?).to be true
        expect(SalesLedger::Entry.where(ticket_number: "T-001").count).to eq(0)
        expect(SalesLedger::Entry.where(ticket_number: "T-002").count).to eq(1)
        expect(result.record.failed_rows_count).to eq(2)
      end

      it "rejects all rows of a ticket when seller_name differs between rows" do
        csv = build_csv_tracked([
          [ "2024-01-15", "T-001", "AAA", "Part A", "1", "100.00", "100.00", "cash", "Juan" ],
          [ "2024-01-15", "T-001", "BBB", "Part B", "1", "100.00", "100.00", "cash", "Pedro" ]  # different seller
        ])
        result = described_class.call(file: csv, filename: "sales.csv")
        expect(SalesLedger::Entry.where(ticket_number: "T-001").count).to eq(0)
        expect(result.record.failed_rows_count).to eq(2)
      end

      it "rejects all rows of a ticket when sale_date differs between rows" do
        csv = build_csv_tracked([
          [ "2024-01-15", "T-001", "AAA", "Part A", "1", "100.00", "100.00", "cash", "Juan" ],
          [ "2024-01-16", "T-001", "BBB", "Part B", "1", "100.00", "100.00", "cash", "Juan" ]  # different date
        ])
        result = described_class.call(file: csv, filename: "sales.csv")
        expect(SalesLedger::Entry.where(ticket_number: "T-001").count).to eq(0)
        expect(result.record.failed_rows_count).to eq(2)
      end

      it "rejects all rows of a ticket when ticket_total_amount differs between rows" do
        csv = build_csv_tracked([
          [ "2024-01-15", "T-001", "AAA", "Part A", "1", "100.00", "200.00", "cash", "Juan" ],
          [ "2024-01-15", "T-001", "BBB", "Part B", "1", "100.00", "300.00", "cash", "Juan" ]  # different total
        ])
        result = described_class.call(file: csv, filename: "sales.csv")
        expect(SalesLedger::Entry.where(ticket_number: "T-001").count).to eq(0)
        expect(result.record.failed_rows_count).to eq(2)
      end

      it "imports other tickets normally when one ticket is rejected for inconsistency" do
        csv = build_csv_tracked([
          [ "2024-01-15", "T-BAD", "AAA", "Part", "1", "100.00", "100.00", "cash", "Juan" ],
          [ "2024-01-15", "T-BAD", "BBB", "Part", "1", "100.00", "100.00", "bank", "Juan" ],  # inconsistent payment_method
          [ "2024-01-15", "T-OK",  "CCC", "Part", "2", "300.00", "600.00", "cash", "Juan" ]   # valid separate ticket
        ])
        described_class.call(file: csv, filename: "sales.csv")
        expect(SalesLedger::Entry.where(ticket_number: "T-OK").count).to eq(1)
        expect(SalesLedger::Entry.where(ticket_number: "T-BAD").count).to eq(0)
      end
    end

    # ── CASE 10: ticket_amount_mismatch flag ──────────────────────────────────
    # mismatch = true when |declared_total - sum(qty * price)| > 0.01
    # mismatch = false otherwise (including within tolerance)
    # The flag is set on ALL rows of the ticket consistently.
    context "ticket_amount_mismatch flag" do
      it "sets ticket_amount_mismatch = false when declared total matches calculated sum" do
        # 2 * 1500.00 = 3000.00
        csv = build_csv_tracked([ [ "2024-01-15", "T-001", "12345", "Filter", "2", "1500.00", "3000.00", "cash", "Juan" ] ])
        described_class.call(file: csv, filename: "sales.csv")
        entry = SalesLedger::Entry.find_by(ticket_number: "T-001")
        expect(entry.ticket_amount_mismatch).to be false
      end

      it "sets ticket_amount_mismatch = true when declared total differs from calculated sum" do
        # 2 * 1500.00 = 3000.00, but declared = 3500.00
        csv = build_csv_tracked([ [ "2024-01-15", "T-001", "12345", "Filter", "2", "1500.00", "3500.00", "cash", "Juan" ] ])
        described_class.call(file: csv, filename: "sales.csv")
        entry = SalesLedger::Entry.find_by(ticket_number: "T-001")
        expect(entry.ticket_amount_mismatch).to be true
      end

      it "marks ALL rows of the ticket with ticket_amount_mismatch when the ticket total is off" do
        # declared 999.00, calculated 1*100 + 2*100 = 300.00
        csv = build_csv_tracked([
          [ "2024-01-15", "T-001", "AAA", "Part A", "1", "100.00", "999.00", "cash", "Juan" ],
          [ "2024-01-15", "T-001", "BBB", "Part B", "2", "100.00", "999.00", "cash", "Juan" ]
        ])
        described_class.call(file: csv, filename: "sales.csv")
        entries = SalesLedger::Entry.where(ticket_number: "T-001")
        expect(entries.count).to eq(2)
        expect(entries.all?(&:ticket_amount_mismatch)).to be true
      end

      it "does not flag as mismatch when difference is exactly 0.01 (boundary of tolerance)" do
        # 1 * 100.00 = 100.00, declared = 100.01 → diff = 0.01 → NOT mismatch (boundary)
        csv = build_csv_tracked([ [ "2024-01-15", "T-001", "12345", "Filter", "1", "100.00", "100.01", "cash", "Juan" ] ])
        described_class.call(file: csv, filename: "sales.csv")
        entry = SalesLedger::Entry.find_by(ticket_number: "T-001")
        expect(entry.ticket_amount_mismatch).to be false
      end

      it "flags as mismatch when difference exceeds 0.01" do
        # 1 * 100.00 = 100.00, declared = 100.02 → diff = 0.02 → IS mismatch
        csv = build_csv_tracked([ [ "2024-01-15", "T-001", "12345", "Filter", "1", "100.00", "100.02", "cash", "Juan" ] ])
        described_class.call(file: csv, filename: "sales.csv")
        entry = SalesLedger::Entry.find_by(ticket_number: "T-001")
        expect(entry.ticket_amount_mismatch).to be true
      end
    end
  end
end
