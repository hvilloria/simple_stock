require "rails_helper"

RSpec.describe Payments::CashRounding do
  describe ".round_up_to_hundred" do
    {
      639_697.5 => 639_700,
      950       => 1_000,
      450       => 500,
      900       => 900,
      1_000     => 1_000,
      45        => 100,
      101       => 200,
      1         => 100,
      0         => 0
    }.each do |input, expected|
      it "rounds #{input} up to #{expected}" do
        expect(described_class.round_up_to_hundred(input)).to eq(expected)
      end
    end

    it "returns an Integer" do
      expect(described_class.round_up_to_hundred(450)).to be_a(Integer)
    end
  end
end
