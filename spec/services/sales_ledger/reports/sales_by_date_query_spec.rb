# frozen_string_literal: true

require "rails_helper"

RSpec.describe SalesLedger::Reports::SalesByDateQuery do
  let(:from) { Date.new(2026, 1, 1) }
  let(:to)   { Date.new(2026, 1, 31) }

  describe ".call" do
    context "product_source filter" do
      before do
        create(:sales_ledger_entry,
               product_source: "local",
               sale_date: from,
               payment_method: "cash",
               ticket_number: "T-LOCAL")

        create(:sales_ledger_entry,
               product_source: "importado",
               sale_date: from + 1.day,
               payment_method: "cash",
               ticket_number: "T-IMPORT")
      end

      it "returns rows for all sources when product_source is nil" do
        results = described_class.call(from: from, to: to)
        dates = results.map(&:sale_date)

        expect(dates).to include(from, from + 1.day)
      end

      it "returns only rows matching 'local'" do
        results = described_class.call(from: from, to: to, product_source: "local")
        dates = results.map(&:sale_date)

        expect(dates).to     include(from)
        expect(dates).not_to include(from + 1.day)
      end

      it "returns only rows matching 'importado'" do
        results = described_class.call(from: from, to: to, product_source: "importado")
        dates = results.map(&:sale_date)

        expect(dates).to     include(from + 1.day)
        expect(dates).not_to include(from)
      end
    end

    context "date range" do
      it "excludes entries outside the range" do
        create(:sales_ledger_entry, sale_date: from, payment_method: "cash", ticket_number: "T-IN")
        create(:sales_ledger_entry, sale_date: from - 1.day, payment_method: "cash", ticket_number: "T-OUT")

        results = described_class.call(from: from, to: to)
        dates = results.map(&:sale_date)

        expect(dates).to     include(from)
        expect(dates).not_to include(from - 1.day)
      end
    end
  end
end
