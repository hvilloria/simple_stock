require "rails_helper"

RSpec.describe Payments::CashRounding do
  describe ".round_to_nearest_hundred" do
    {
      639_697.5 => 639_700,  # remainder 97.5 → up
      22_050    => 22_000,   # remainder 50 (tie) → down
      22_051    => 22_100,   # remainder 51 → up
      50        => 0,        # tie → down
      51        => 100,      # → up
      150       => 100,      # remainder 50 (tie) → down
      151       => 200,      # → up
      900       => 900,      # exact multiple
      1_000     => 1_000,    # exact multiple
      0         => 0
    }.each do |input, expected|
      it "rounds #{input} to nearest hundred => #{expected}" do
        expect(described_class.round_to_nearest_hundred(input)).to eq(expected)
      end
    end

    it "returns an Integer" do
      expect(described_class.round_to_nearest_hundred(450)).to be_a(Integer)
    end
  end
end
