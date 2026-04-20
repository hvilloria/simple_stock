# frozen_string_literal: true

require "rails_helper"

RSpec.describe SalesLedger::Reports::TopProductsQuery do
  let(:from) { Date.new(2026, 1, 1) }
  let(:to)   { Date.new(2026, 1, 31) }

  describe ".call" do
    context "frequency ordering" do
      it "ranks OEM with more distinct tickets higher" do
        create(:sales_ledger_entry, oem_code: "OEM_A", ticket_number: "T-001", sale_date: from)
        create(:sales_ledger_entry, oem_code: "OEM_A", ticket_number: "T-002", sale_date: from)
        create(:sales_ledger_entry, oem_code: "OEM_B", ticket_number: "T-003", sale_date: from)

        results = described_class.call(from: from, to: to)

        expect(results.first.oem_code).to eq("OEM_A")
        expect(results.first.frequency).to eq(2)
        expect(results.second.oem_code).to eq("OEM_B")
        expect(results.second.frequency).to eq(1)
      end

      it "counts the same ticket_number only once per OEM" do
        create(:sales_ledger_entry, oem_code: "OEM_A", ticket_number: "T-001", sale_date: from)
        create(:sales_ledger_entry, oem_code: "OEM_A", ticket_number: "T-001", sale_date: from)

        results = described_class.call(from: from, to: to)

        expect(results.first.oem_code).to eq("OEM_A")
        expect(results.first.frequency).to eq(1)
      end
    end

    context "product_source filter" do
      before do
        create(:sales_ledger_entry, oem_code: "LOCAL_OEM",  product_source: "local",     sale_date: from)
        create(:sales_ledger_entry, oem_code: "IMPORT_OEM", product_source: "importado",  sale_date: from)
      end

      it "returns all entries when product_source is nil" do
        results = described_class.call(from: from, to: to)
        oem_codes = results.map(&:oem_code)

        expect(oem_codes).to include("LOCAL_OEM", "IMPORT_OEM")
      end

      it "returns only local entries when filtered by 'local'" do
        results = described_class.call(from: from, to: to, product_source: "local")
        oem_codes = results.map(&:oem_code)

        expect(oem_codes).to     include("LOCAL_OEM")
        expect(oem_codes).not_to include("IMPORT_OEM")
      end

      it "returns only importado entries when filtered by 'importado'" do
        results = described_class.call(from: from, to: to, product_source: "importado")
        oem_codes = results.map(&:oem_code)

        expect(oem_codes).to     include("IMPORT_OEM")
        expect(oem_codes).not_to include("LOCAL_OEM")
      end
    end

    context "date range" do
      it "excludes entries outside the range" do
        create(:sales_ledger_entry, oem_code: "IN_RANGE",  sale_date: from)
        create(:sales_ledger_entry, oem_code: "OUT_RANGE", sale_date: from - 1.day)

        results = described_class.call(from: from, to: to)
        oem_codes = results.map(&:oem_code)

        expect(oem_codes).to     include("IN_RANGE")
        expect(oem_codes).not_to include("OUT_RANGE")
      end
    end

    context "limit" do
      it "respects the limit parameter" do
        5.times { |i| create(:sales_ledger_entry, oem_code: "OEM_#{i}", ticket_number: "T-#{i}", sale_date: from) }

        results = described_class.call(from: from, to: to, limit: 3)

        expect(results.length).to eq(3)
      end
    end
  end
end
