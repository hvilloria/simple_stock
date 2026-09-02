# frozen_string_literal: true

require "rails_helper"

RSpec.describe CurrencyParser do
  let(:includer) { Class.new { include CurrencyParser }.new }

  def decimal_string_from(raw)
    includer.send(:decimal_string_from, raw)
  end

  describe "#decimal_string_from" do
    it "normalizes a full Argentine amount" do
      expect(decimal_string_from("1.500.000,50")).to eq("1500000.50")
    end

    it "reads a dotted group of three as a thousands separator" do
      expect(decimal_string_from("101.800")).to eq("101800")
    end

    it "leaves a plain decimal alone" do
      expect(decimal_string_from("200000.50")).to eq("200000.50")
    end

    it "returns nil for something that is not a number" do
      expect(decimal_string_from("abc")).to be_nil
    end

    it "returns nil for a blank string" do
      expect(decimal_string_from("")).to be_nil
    end

    it "returns nil for nil" do
      expect(decimal_string_from(nil)).to be_nil
    end
  end
end
