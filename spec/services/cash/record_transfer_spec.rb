# frozen_string_literal: true

require "rails_helper"

RSpec.describe Cash::RecordTransfer do
  let(:user) { create(:user, :caja) }
  let(:day) { Date.new(2026, 8, 3) }

  def call(**overrides)
    described_class.call(
      **{
        from: "drawer",
        to: "main_cash",
        amount: 200_000,
        business_date: day,
        user: user
      }.merge(overrides)
    )
  end

  describe "success" do
    it "writes two legs with opposite signs sharing one transfer_group_id" do
      result = call

      expect(result).to be_success
      expect(CashMovement.count).to eq(2)

      outflow, inflow = result.record

      expect(outflow.account).to eq("drawer")
      expect(outflow.amount).to eq(-200_000)
      expect(inflow.account).to eq("main_cash")
      expect(inflow.amount).to eq(200_000)

      expect(outflow.transfer_group_id).to be_present
      expect(inflow.transfer_group_id).to eq(outflow.transfer_group_id)
    end

    it "categorises both legs as an internal transfer with no channel or subcategory" do
      call

      CashMovement.find_each do |movement|
        expect(movement.category).to eq("internal_transfer")
        expect(movement.channel).to be_nil
        expect(movement.subcategory).to be_nil
        expect(movement.business_date).to eq(day)
        expect(movement.user).to eq(user)
      end
    end

    it "moves each arca's balance by the transferred amount" do
      create(:cash_movement, account: "drawer", amount: 500_000)

      call(amount: 200_000)

      expect(CashMovement.balance_for("drawer")).to eq(300_000)
      expect(CashMovement.balance_for("main_cash")).to eq(200_000)
    end

    it "stores the description on both legs" do
      call(description: "Cierre de caja del día")

      expect(CashMovement.pluck(:description).uniq).to eq([ "Cierre de caja del día" ])
    end

    it "accepts a plain decimal string without losing precision" do
      result = call(amount: "200000.50")

      expect(result).to be_success
      expect(result.record.map(&:amount)).to eq([ BigDecimal("-200000.50"), BigDecimal("200000.50") ])
    end
  end

  describe "failure" do
    it "refuses a transfer to the same arca" do
      result = call(from: "drawer", to: "drawer")

      expect(result).to be_failure
      expect(CashMovement.count).to eq(0)
    end

    it "refuses an unknown origin arca" do
      result = call(from: "petty_cash")

      expect(result).to be_failure
      expect(CashMovement.count).to eq(0)
    end

    it "refuses an unknown destination arca" do
      result = call(to: "petty_cash")

      expect(result).to be_failure
      expect(CashMovement.count).to eq(0)
    end

    it "refuses a blank origin or destination" do
      [ { from: nil }, { to: nil } ].each do |overrides|
        result = call(**overrides)

        expect(result).to be_failure, "expected #{overrides.inspect} to be rejected"
        expect(CashMovement.count).to eq(0)
      end
    end

    it "refuses a negative amount instead of swapping the direction" do
      result = call(amount: -200_000)

      expect(result).to be_failure
      expect(CashMovement.count).to eq(0)
    end

    it "refuses a missing user" do
      result = call(user: nil)

      expect(result).to be_failure
      expect(CashMovement.count).to eq(0)
    end

    it "refuses a missing business_date" do
      result = call(business_date: nil)

      expect(result).to be_failure
      expect(CashMovement.count).to eq(0)
    end
  end

  describe "hostile input" do
    it "refuses amounts that a lenient parser would silently mangle" do
      [ "1.500", "1.500.000,50", "101.800", "abc", "", "1e6", "1_000", nil, 0 ].each do |hostile|
        result = call(amount: hostile)

        expect(result).to be_failure, "expected #{hostile.inspect} to be rejected"
        expect(CashMovement.count).to eq(0)
      end
    end
  end

  describe "atomicity" do
    it "leaves zero rows when the second leg fails after the first was written" do
      call_count = 0
      rows_when_second_leg_ran = nil

      allow(CashMovement).to receive(:create!).and_wrap_original do |original, *args, **kwargs|
        call_count += 1
        if call_count == 2
          rows_when_second_leg_ran = CashMovement.count
          raise ActiveRecord::RecordInvalid, CashMovement.new
        end
        original.call(*args, **kwargs)
      end

      result = call

      expect(call_count).to eq(2)
      # The first leg really reached the database before the second one blew up.
      expect(rows_when_second_leg_ran).to eq(1)
      expect(result).to be_failure
      expect(CashMovement.count).to eq(0)
    end
  end
end
