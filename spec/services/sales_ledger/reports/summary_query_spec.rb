# frozen_string_literal: true

require "rails_helper"

RSpec.describe SalesLedger::Reports::SummaryQuery do
  let(:from) { Date.new(2026, 1, 1) }
  let(:to)   { Date.new(2026, 1, 31) }

  describe ".call" do
    context "product_source filter" do
      before do
        create(:sales_ledger_entry,
               product_source: "local",
               sale_date: from,
               quantity: 3,
               unit_price: BigDecimal("1000"),
               total_amount: BigDecimal("3000"),
               ticket_total_amount: BigDecimal("3000"),
               payment_method: "cash",
               ticket_number: "T-LOCAL")

        create(:sales_ledger_entry,
               product_source: "importado",
               sale_date: from,
               quantity: 5,
               unit_price: BigDecimal("2000"),
               total_amount: BigDecimal("10000"),
               ticket_total_amount: BigDecimal("10000"),
               payment_method: "cash",
               ticket_number: "T-IMPORT")
      end

      it "counts all entries when product_source is nil" do
        result = described_class.call(from: from, to: to)

        expect(result[:units]).to eq(8)
        expect(result[:tickets]).to eq(2)
      end

      it "counts only local entries when filtered by 'local'" do
        result = described_class.call(from: from, to: to, product_source: "local")

        expect(result[:units]).to eq(3)
        expect(result[:tickets]).to eq(1)
      end

      it "counts only importado entries when filtered by 'importado'" do
        result = described_class.call(from: from, to: to, product_source: "importado")

        expect(result[:units]).to eq(5)
        expect(result[:tickets]).to eq(1)
      end
    end

    context "date range" do
      it "excludes entries outside the range" do
        create(:sales_ledger_entry, sale_date: from, quantity: 2)
        create(:sales_ledger_entry, sale_date: from - 1.day, quantity: 10)

        result = described_class.call(from: from, to: to)

        expect(result[:units]).to eq(2)
      end
    end
  end
end
