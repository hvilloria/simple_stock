# frozen_string_literal: true

require "rails_helper"

RSpec.describe CurrencyParser do
  subject(:parser) do
    Class.new do
      include CurrencyParser

      # parse_amount is private in the concern; expose it for the unit spec.
      public :parse_amount
    end.new
  end

  describe "#parse_amount" do
    context "Argentine format (comma is the decimal separator)" do
      it { expect(parser.parse_amount("1.500.000,50")).to eq(BigDecimal("1500000.50")) }
      it { expect(parser.parse_amount("1.500,00")).to eq(BigDecimal("1500")) }
      it { expect(parser.parse_amount("80.000,00")).to eq(BigDecimal("80000")) }
      it { expect(parser.parse_amount("22.000,00")).to eq(BigDecimal("22000")) }
      it { expect(parser.parse_amount("999,99")).to eq(BigDecimal("999.99")) }
      it { expect(parser.parse_amount("1500,50")).to eq(BigDecimal("1500.50")) }
      it { expect(parser.parse_amount("-1.500.000,50")).to eq(BigDecimal("-1500000.50")) }
    end

    context "Argentine thousands with no decimals (more than one dot)" do
      it { expect(parser.parse_amount("1.500.000")).to eq(BigDecimal("1500000")) }
      it { expect(parser.parse_amount("1.200.300")).to eq(BigDecimal("1200300")) }
    end

    context "a single dot is a decimal point, not a thousands separator" do
      it { expect(parser.parse_amount("1.200")).to eq(BigDecimal("1.2")) }
    end

    context "malformed grouping (a wrong number would be worse than nil)" do
      it { expect(parser.parse_amount("1..5")).to be_nil }
      it { expect(parser.parse_amount("12.34.56")).to be_nil }
      it { expect(parser.parse_amount("1.2.3,45")).to be_nil }
      it { expect(parser.parse_amount("1.5000,00")).to be_nil }
      it { expect(parser.parse_amount("1.500.00")).to be_nil }
      it { expect(parser.parse_amount("1234.567.890")).to be_nil }
    end

    context "already numeric input" do
      it { expect(parser.parse_amount(1500)).to eq(BigDecimal("1500")) }
      it { expect(parser.parse_amount(BigDecimal("1500.50"))).to eq(BigDecimal("1500.50")) }
      it { expect(parser.parse_amount(1500.50)).to eq(BigDecimal("1500.50")) }
      it { expect(parser.parse_amount(0)).to eq(BigDecimal("0")) }
    end

    context "clean decimal (what currency-input JS submits)" do
      it { expect(parser.parse_amount("1500.50")).to eq(BigDecimal("1500.50")) }
      it { expect(parser.parse_amount("1500000.50")).to eq(BigDecimal("1500000.50")) }
      it { expect(parser.parse_amount("0.01")).to eq(BigDecimal("0.01")) }
    end

    context "plain integers" do
      it { expect(parser.parse_amount("1500")).to eq(BigDecimal("1500")) }
      it { expect(parser.parse_amount("-500")).to eq(BigDecimal("-500")) }
      it { expect(parser.parse_amount("0")).to eq(BigDecimal("0")) }
    end

    context "unparseable input" do
      it { expect(parser.parse_amount("abc")).to be_nil }
      it { expect(parser.parse_amount("1.500,00,00")).to be_nil }
      it { expect(parser.parse_amount("$1.500")).to be_nil }
      it { expect(parser.parse_amount("1 500")).to be_nil }
      it { expect(parser.parse_amount("--500")).to be_nil }
      it { expect(parser.parse_amount("1e5")).to be_nil }
      it { expect(parser.parse_amount("+500")).to be_nil }
      it { expect(parser.parse_amount(",50")).to be_nil }
      it { expect(parser.parse_amount("1,")).to be_nil }
    end

    context "blank input" do
      it { expect(parser.parse_amount("")).to be_nil }
      it { expect(parser.parse_amount("   ")).to be_nil }
      it { expect(parser.parse_amount(nil)).to be_nil }
    end

    it "returns a BigDecimal, never a Float" do
      expect(parser.parse_amount("1500.50")).to be_a(BigDecimal)
    end

    it "never returns zero as a stand-in for invalid input" do
      expect(parser.parse_amount("abc")).not_to eq(0)
    end

    it "strips surrounding whitespace" do
      expect(parser.parse_amount("  1.500,50  ")).to eq(BigDecimal("1500.50"))
    end
  end
end
