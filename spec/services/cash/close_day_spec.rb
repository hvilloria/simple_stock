# frozen_string_literal: true

require "rails_helper"

RSpec.describe Cash::CloseDay do
  let(:user) { create(:user, :caja) }
  let(:day) { Date.new(2026, 8, 3) }

  def close(**overrides)
    described_class.call(
      **{
        business_date: day,
        counted_cash: 0,
        user: user
      }.merge(overrides)
    )
  end

  def drawer_movement(amount, **attrs)
    create(:cash_movement, { business_date: day, account: "drawer", amount: amount }.merge(attrs))
  end

  # The single claim the whole close rests on: whatever the day held and
  # whatever was counted, the drawer ends the day empty.
  describe "the drawer lands on exactly zero" do
    it "when the count matches the expectation" do
      drawer_movement(299_700)

      expect(close(counted_cash: 299_700)).to be_success
      expect(CashMovement.drawer_balance_on(day)).to eq(0)
    end

    it "when the count is short" do
      drawer_movement(299_700)

      expect(close(counted_cash: 289_700)).to be_success
      expect(CashMovement.drawer_balance_on(day)).to eq(0)
    end

    it "when the count is over" do
      drawer_movement(299_700)

      expect(close(counted_cash: 305_000)).to be_success
      expect(CashMovement.drawer_balance_on(day)).to eq(0)
    end

    it "when the expected amount is negative and nothing was counted" do
      drawer_movement(50_000)
      drawer_movement(-350_000, category: "suppliers", channel: nil)

      expect(close(counted_cash: 0)).to be_success
      expect(CashMovement.drawer_balance_on(day)).to eq(0)
    end

    it "when both the expectation and the count are zero" do
      expect(close(counted_cash: 0)).to be_success
      expect(CashMovement.drawer_balance_on(day)).to eq(0)
    end
  end

  describe "the discrepancy" do
    it "records the exact difference as a cash_discrepancy on the drawer" do
      drawer_movement(299_700)

      close(counted_cash: 289_700)

      discrepancy = CashMovement.find_by(category: "cash_discrepancy")
      expect(discrepancy.amount).to eq(-10_000)
      expect(discrepancy.account).to eq("drawer")
      expect(discrepancy.business_date).to eq(day)
      expect(discrepancy.channel).to be_nil
      expect(discrepancy.subcategory).to be_nil
      expect(discrepancy.user).to eq(user)
    end

    it "is absent when the count matches" do
      drawer_movement(299_700)

      close(counted_cash: 299_700)

      expect(CashMovement.where(category: "cash_discrepancy")).to be_empty
    end

    it "is positive when the day's cash expenses exceeded its cash sales" do
      drawer_movement(50_000)
      drawer_movement(-350_000, category: "suppliers", channel: nil)

      close(counted_cash: 0)

      expect(CashMovement.find_by(category: "cash_discrepancy").amount).to eq(300_000)
    end

    it "leaves the movements it disagrees with untouched" do
      sale = drawer_movement(299_700)

      close(counted_cash: 289_700)

      expect(sale.reload.amount).to eq(299_700)
    end

    it "carries the note as its description" do
      drawer_movement(299_700)

      close(counted_cash: 289_700, note: "Faltó un billete de 10.000")

      expect(CashMovement.find_by(category: "cash_discrepancy").description)
        .to eq("Faltó un billete de 10.000")
    end
  end

  describe "the transfer to the bundles" do
    it "moves the counted amount from the drawer to the main cash" do
      drawer_movement(299_700)

      close(counted_cash: 299_700)

      legs = CashMovement.where(category: "internal_transfer").order(:amount)
      expect(legs.map(&:account)).to eq(%w[drawer main_cash])
      expect(legs.map(&:amount)).to eq([ -299_700, 299_700 ])
      expect(legs.pluck(:transfer_group_id).uniq.size).to eq(1)
      expect(CashMovement.balance_for("main_cash")).to eq(299_700)
    end

    it "wraps what was counted, not what was expected" do
      drawer_movement(299_700)

      close(counted_cash: 289_700)

      expect(CashMovement.balance_for("main_cash")).to eq(289_700)
    end

    it "writes no transfer when nothing was counted" do
      drawer_movement(50_000)

      close(counted_cash: 0)

      expect(CashMovement.where(category: "internal_transfer")).to be_empty
    end
  end

  describe "sealing" do
    it "stamps the closing id on every movement of the date, including the rows it just wrote" do
      drawer_movement(299_700)

      result = close(counted_cash: 289_700)

      closing = result.record
      expect(CashMovement.on(day).count).to eq(4)
      expect(CashMovement.on(day).pluck(:daily_closing_id).uniq).to eq([ closing.id ])
    end

    it "seals movements of the date whatever their arca" do
      create(:cash_movement, :card_sale, business_date: day)

      result = close(counted_cash: 0)

      expect(CashMovement.for_account("bank").on(day).first.daily_closing_id).to eq(result.record.id)
    end

    it "leaves a movement of another date unsealed" do
      other = create(:cash_movement, business_date: day + 1.day)

      close(counted_cash: 0)

      expect(other.reload.daily_closing_id).to be_nil
    end
  end

  describe "the closing record" do
    it "persists the expectation, the count and the verification totals" do
      drawer_movement(299_700)

      result = close(counted_cash: 289_700, payway_batch_total: 109_020, mercado_pago_total: 77_200)

      closing = result.record
      expect(closing).to be_persisted
      expect(closing.business_date).to eq(day)
      expect(closing.expected_cash).to eq(299_700)
      expect(closing.counted_cash).to eq(289_700)
      expect(closing.payway_batch_total).to eq(109_020)
      expect(closing.mercado_pago_total).to eq(77_200)
      expect(closing.closed_at).to be_present
      expect(closing.user).to eq(user)
    end

    it "records the expectation as it stood before the discrepancy was written" do
      drawer_movement(299_700)

      result = close(counted_cash: 100)

      expect(result.record.expected_cash).to eq(299_700)
    end

    it "leaves both verification totals blank when they are not supplied" do
      result = close(counted_cash: 0)

      expect(result.record.payway_batch_total).to be_nil
      expect(result.record.mercado_pago_total).to be_nil
    end

    it "accepts a plain decimal string without losing precision" do
      drawer_movement(299_700)

      result = close(counted_cash: "289700.50")

      expect(result.record.counted_cash).to eq(BigDecimal("289700.50"))
    end
  end

  describe "failure" do
    it "refuses a second close of the same date and writes nothing" do
      drawer_movement(299_700)
      close(counted_cash: 299_700)
      movements_after_first = CashMovement.count

      result = close(counted_cash: 500)

      expect(result).to be_failure
      expect(result.errors).to include(/ya fue cerrado/)
      expect(DailyClosing.count).to eq(1)
      expect(CashMovement.count).to eq(movements_after_first)
    end

    it "refuses a close with no user" do
      result = close(user: nil)

      expect(result).to be_failure
      expect(DailyClosing.count).to eq(0)
    end

    it "refuses a close with no date" do
      result = close(business_date: nil)

      expect(result).to be_failure
      expect(DailyClosing.count).to eq(0)
    end

    it "refuses a count that is not a trustworthy amount" do
      result = close(counted_cash: "289.700")

      expect(result).to be_failure
      expect(DailyClosing.count).to eq(0)
      expect(CashMovement.count).to eq(0)
    end

    it "refuses a negative count" do
      result = close(counted_cash: -100)

      expect(result).to be_failure
      expect(DailyClosing.count).to eq(0)
    end

    it "refuses a verification total that is not a trustworthy amount" do
      result = close(counted_cash: 0, payway_batch_total: "109.020")

      expect(result).to be_failure
      expect(DailyClosing.count).to eq(0)
    end

    it "rolls back the whole close when a step fails" do
      sale = drawer_movement(299_700)
      allow(Cash::RecordTransfer).to receive(:call).and_raise(ActiveRecord::StatementInvalid, "boom")

      result = close(counted_cash: 289_700)

      expect(result).to be_failure
      expect(DailyClosing.count).to eq(0)
      expect(CashMovement.count).to eq(1)
      expect(sale.reload.daily_closing_id).to be_nil
    end

    it "rolls back when sealing hits a movement another closing already sealed" do
      drawer_movement(299_700)
      allow_any_instance_of(CashMovement)
        .to receive(:update!).and_raise(CashMovement::SealedMovementError, "sealed")

      result = close(counted_cash: 299_700)

      expect(result).to be_failure
      expect(DailyClosing.count).to eq(0)
      expect(CashMovement.count).to eq(1)
    end
  end
end
