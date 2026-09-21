# frozen_string_literal: true

require "rails_helper"

RSpec.describe DailyClosing, type: :model do
  describe "associations" do
    it { should belong_to(:user) }
  end

  describe "validations" do
    subject { build(:daily_closing) }

    it { should validate_presence_of(:business_date) }
    it { should validate_presence_of(:expected_cash) }
    it { should validate_presence_of(:counted_cash) }
    it { should validate_uniqueness_of(:business_date) }
  end

  describe "business date" do
    around do |example|
      travel_to Date.new(2026, 8, 3) do
        example.run
      end
    end

    it "rejects a closing dated tomorrow" do
      closing = build(:daily_closing, business_date: Date.new(2026, 8, 4))
      expect(closing).not_to be_valid
      expect(closing.errors[:base]).to include(
        "La fecha no puede ser futura: un día se cierra cuando ya llegó."
      )
    end

    it "accepts a closing dated today" do
      expect(build(:daily_closing, business_date: Date.new(2026, 8, 3))).to be_valid
    end

    it "accepts a closing dated yesterday" do
      expect(build(:daily_closing, business_date: Date.new(2026, 8, 2))).to be_valid
    end
  end

  describe "verification columns" do
    it "allows both to be nil, meaning not verified" do
      closing = build(:daily_closing, payway_batch_total: nil, mercado_pago_total: nil)
      expect(closing).to be_valid
    end

    it "keeps nil distinct from zero" do
      closing = create(:daily_closing, payway_batch_total: nil, mercado_pago_total: 0)
      expect(closing.reload.payway_batch_total).to be_nil
      expect(closing.reload.mercado_pago_total).to eq(0)
    end
  end

  describe "sealed movements" do
    it "cannot be destroyed once it seals movements" do
      closing = create(:daily_closing)
      create(:cash_movement, daily_closing: closing, business_date: closing.business_date)

      expect { closing.destroy }.to raise_error(ActiveRecord::DeleteRestrictionError)
    end
  end

  describe "#difference" do
    it "is zero when the count matches" do
      closing = build(:daily_closing, expected_cash: 311_700, counted_cash: 311_700)
      expect(closing.difference).to eq(0)
    end

    it "is negative on a shortfall" do
      closing = build(:daily_closing, expected_cash: 311_700, counted_cash: 291_700)
      expect(closing.difference).to eq(-20_000)
    end

    it "is positive on a surplus" do
      closing = build(:daily_closing, expected_cash: 311_700, counted_cash: 320_000)
      expect(closing.difference).to eq(8_300)
    end
  end
end
