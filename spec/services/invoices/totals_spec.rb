require "rails_helper"

RSpec.describe Invoices::Totals do
  describe "an invoice with discount and IVA (Yokomitsu 10197)" do
    subject(:totals) { described_class.new(subtotal: 338_354.40, discount_percentage: 10, iva_percentage: 21) }

    it "breaks the subtotal down like the paper invoice" do
      expect(totals.subtotal).to eq(BigDecimal("338354.40"))
      expect(totals.discount).to eq(BigDecimal("33835.44"))
      expect(totals.iva).to eq(BigDecimal("63948.98"))
      expect(totals.total).to eq(BigDecimal("368467.94"))
    end
  end

  it "totals Yokomitsu 10196 (discount 25, IVA 21)" do
    totals = described_class.new(subtotal: 1_276_410, discount_percentage: 25, iva_percentage: 21)

    expect(totals.total).to eq(BigDecimal("1158342.08"))
  end

  it "totals Impomotors (no discount, IVA 21)" do
    totals = described_class.new(subtotal: 1_008_835.11, discount_percentage: 0, iva_percentage: 21)

    expect(totals.discount).to be_zero
    expect(totals.total).to eq(BigDecimal("1220690.48"))
  end

  it "keeps the subtotal when there is neither discount nor IVA" do
    totals = described_class.new(subtotal: 1_500.50, discount_percentage: 0, iva_percentage: 0)

    expect(totals.total).to eq(BigDecimal("1500.50"))
  end

  it "accepts BigDecimal inputs" do
    totals = described_class.new(subtotal: BigDecimal("338354.40"), discount_percentage: BigDecimal("10"), iva_percentage: BigDecimal("21"))

    expect(totals.total).to eq(BigDecimal("368467.94"))
  end

  describe ".final_unit_cost" do
    it "applies the discount and then the IVA to the unit price" do
      cost = described_class.final_unit_cost(8_900, discount_percentage: 10, iva_percentage: 21)

      expect(cost).to be_a(BigDecimal)
      expect(cost).to eq(BigDecimal("9692.10"))
    end

    it "is zero with a full discount" do
      expect(described_class.final_unit_cost(8_900, discount_percentage: 100, iva_percentage: 21)).to be_zero
    end
  end
end
