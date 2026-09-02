# frozen_string_literal: true

require "rails_helper"

RSpec.describe Cash::RecordMovement do
  let(:user) { create(:user, :caja) }
  let(:day) { Date.new(2026, 8, 3) }

  def call(**overrides)
    described_class.call(
      **{
        business_date: day,
        account: "drawer",
        amount: 299_700,
        category: "sale",
        channel: "cash",
        user: user
      }.merge(overrides)
    )
  end

  describe "success" do
    it "persists the movement and returns it" do
      result = call

      expect(result).to be_success
      expect(result.record).to be_persisted
      expect(result.record.amount).to eq(299_700)
      expect(result.record.account).to eq("drawer")
      expect(result.record.user).to eq(user)
    end

    it "records an outflow as a negative amount" do
      result = call(category: "fixed_expense", subcategory: "store_expenses",
                    channel: nil, amount: -13_000)

      expect(result).to be_success
      expect(result.record.amount).to eq(-13_000)
      expect(result.record).to be_outflow
    end

    it "records a compensation sale with no arca" do
      result = call(channel: "compensation", account: nil, amount: 661_188)

      expect(result).to be_success
      expect(result.record.account).to be_nil
    end
  end

  describe "failure" do
    it "rejects a zero amount" do
      result = call(amount: 0)

      expect(result).to be_failure
      expect(result.errors.join).to match(/amount/i)
      expect(CashMovement.count).to eq(0)
    end

    it "rejects a sale with no channel" do
      result = call(channel: nil)

      expect(result).to be_failure
      expect(CashMovement.count).to eq(0)
    end

    it "rejects a missing business_date" do
      result = call(business_date: nil)

      expect(result).to be_failure
      expect(CashMovement.count).to eq(0)
    end

    it "refuses a one-legged internal transfer" do
      result = call(category: "internal_transfer", channel: nil, amount: 100)

      expect(result).to be_failure
      expect(CashMovement.count).to eq(0)
    end

    it "rejects a missing user" do
      result = call(user: nil)

      expect(result).to be_failure
      expect(CashMovement.count).to eq(0)
    end
  end

  describe "hostile input" do
    it "rejects an AR-formatted string instead of silently truncating it" do
      result = call(amount: "1.500.000,50")

      expect(result).to be_failure
      expect(CashMovement.count).to eq(0)
    end

    it "rejects a non-numeric amount" do
      result = call(amount: "abc")

      expect(result).to be_failure
      expect(CashMovement.count).to eq(0)
    end

    it "rejects a blank amount" do
      result = call(amount: "")

      expect(result).to be_failure
      expect(CashMovement.count).to eq(0)
    end

    it "rejects a nil amount" do
      result = call(amount: nil)

      expect(result).to be_failure
      expect(CashMovement.count).to eq(0)
    end

    it "accepts a plain decimal string without losing precision" do
      result = call(amount: "200000.50")

      expect(result).to be_success
      expect(result.record.amount).to eq(BigDecimal("200000.50"))
    end

    it "rejects a single-separator thousands string instead of dividing by 1000" do
      [ "1.500", "101.800" ].each do |hostile|
        result = call(amount: hostile)

        expect(result).to be_failure, "expected #{hostile.inspect} to be rejected"
        expect(CashMovement.count).to eq(0)
      end
    end

    it "rejects notations BigDecimal accepts but an amount field never uses" do
      [ "1e6", "1_000" ].each do |hostile|
        result = call(amount: hostile)

        expect(result).to be_failure, "expected #{hostile.inspect} to be rejected"
        expect(CashMovement.count).to eq(0)
      end
    end

    it "keeps accepting the plain decimal strings the rake task passes" do
      [ [ "200000.50", BigDecimal("200000.50") ], [ "-13000", -13_000 ],
        [ "12497899.30", BigDecimal("12497899.30") ], [ "500", 500 ] ].each do |raw, expected|
        result = call(amount: raw)

        expect(result).to be_success, "expected #{raw.inspect} to be accepted"
        expect(result.record.amount).to eq(expected)
        result.record.destroy
      end
    end

    it "rejects an unknown account" do
      result = call(account: "petty_cash")

      expect(result).to be_failure
      expect(CashMovement.count).to eq(0)
    end

    it "rejects an unknown category" do
      result = call(category: "shrinkage")

      expect(result).to be_failure
      expect(CashMovement.count).to eq(0)
    end

    it "rejects an unknown channel" do
      result = call(channel: "crypto")

      expect(result).to be_failure
      expect(CashMovement.count).to eq(0)
    end
  end
end
