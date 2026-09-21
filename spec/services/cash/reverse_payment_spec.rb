# frozen_string_literal: true

require "rails_helper"

RSpec.describe Cash::ReversePayment do
  let(:user) { create(:user, :caja) }
  let(:past_day) { Date.new(2026, 8, 3) }
  let(:today) { Date.new(2026, 9, 2) }

  def collected_payment(method: "cash", amount: 299_700, date: past_day)
    payment = create(:payment, payment_method: method, payment_date: date, amount: amount)
    result = Cash::RecordSaleFromPayment.call(payment: payment, user: user)
    raise result.errors.to_sentence if result.failure?

    [ payment, result.record ]
  end

  describe "the reversing movement" do
    it "mirrors the original with the opposite sign, same arca, channel and payment" do
      payment, original = collected_payment(method: "bank_card", amount: 54_700)

      result = described_class.call(payment: payment, user: user, business_date: today)

      expect(result).to be_success
      expect(result.record.amount).to eq(-original.amount)
      expect(result.record).to be_outflow
      expect(result.record.account).to eq(original.account)
      expect(result.record.channel).to eq(original.channel)
      expect(result.record.category).to eq(original.category)
      expect(result.record.source_payment_id).to eq(payment.id)
      expect(result.record.user).to eq(user)
    end

    it "leaves the arca at zero for the two rows" do
      payment, original = collected_payment

      described_class.call(payment: payment, user: user, business_date: today)

      expect(CashMovement.where(source_payment_id: payment.id).sum(:amount)).to eq(0)
      expect(CashMovement.balance_for(original.account)).to eq(0)
    end

    it "describes what it reverses" do
      payment, = collected_payment

      result = described_class.call(payment: payment, user: user, business_date: today)

      expect(result.record.description).to include("Reversa")
      expect(result.record.description).to include(payment.id.to_s)
    end

    it "lands on today by default, not on the original's business date" do
      payment, = collected_payment

      result = described_class.call(payment: payment, user: user)

      expect(result.record.business_date).to eq(Date.current)
      expect(result.record.business_date).not_to eq(past_day)
    end

    it "never touches the original row" do
      payment, original = collected_payment
      before_amount     = original.amount
      before_updated_at = original.updated_at

      described_class.call(payment: payment, user: user, business_date: today)

      original.reload
      expect(original.amount).to eq(before_amount)
      expect(original.updated_at).to eq(before_updated_at)
      expect(original).to be_persisted
    end
  end

  describe "when the original day is already sealed" do
    let(:payment) { create(:payment, payment_date: past_day, amount: 299_700) }
    let!(:original) do
      create(:cash_movement, :sealed, source_payment: payment, user: user,
                                      business_date: past_day, amount: 299_700)
    end

    it "reverses on today without modifying the sealed row" do
      before_updated_at = original.updated_at

      result = described_class.call(payment: payment, user: user, business_date: today)

      expect(result).to be_success
      expect(result.record.business_date).to eq(today)
      expect(result.record.amount).to eq(-299_700)
      expect(result.record).not_to be_sealed
      expect(original.reload.updated_at).to eq(before_updated_at)
      expect(original.amount).to eq(299_700)
      expect(original).to be_sealed
    end

    # The failure this design avoids: undoing by editing the original would blow up.
    it "would raise if the original were edited instead of reversed" do
      expect { original.update!(amount: 1) }
        .to raise_error(CashMovement::SealedMovementError)
    end
  end

  describe "failure" do
    it "refuses a payment with no cash movement" do
      payment = create(:payment, payment_date: past_day)

      result = described_class.call(payment: payment, user: user, business_date: today)

      expect(result).to be_failure
      expect(CashMovement.count).to eq(0)
    end

    it "refuses to reverse the same payment twice" do
      payment, = collected_payment

      first  = described_class.call(payment: payment, user: user, business_date: today)
      second = described_class.call(payment: payment, user: user, business_date: today)

      expect(first).to be_success
      expect(second).to be_failure
      expect(CashMovement.where(source_payment_id: payment.id).count).to eq(2)
    end

    it "rejects a missing payment" do
      result = described_class.call(payment: nil, user: user)

      expect(result).to be_failure
      expect(CashMovement.count).to eq(0)
    end

    it "rejects a missing user" do
      payment, = collected_payment

      result = described_class.call(payment: payment, user: nil)

      expect(result).to be_failure
      expect(CashMovement.where(source_payment_id: payment.id).count).to eq(1)
    end
  end
end
