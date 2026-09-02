# frozen_string_literal: true

require "rails_helper"

RSpec.describe Cash::RecordSaleFromPayment do
  let(:user) { create(:user, :caja) }
  let(:past_day) { Date.new(2026, 8, 3) }

  def payment_for(method, **overrides)
    create(:payment, payment_method: method, payment_date: past_day, **overrides)
  end

  describe "channel and arca routing" do
    {
      "cash"          => [ "cash", "drawer" ],
      "bank_qr"       => [ "qr", "bank" ],
      "bank_card"     => [ "card", "bank" ],
      "bank_transfer" => [ "transfer", "bank" ],
      "mercado_pago"  => [ "mercado_pago", "mercado_pago" ]
    }.each do |method, (channel, account)|
      it "routes #{method} to the #{channel} channel and the #{account} arca" do
        result = described_class.call(payment: payment_for(method), user: user)

        expect(result).to be_success
        expect(result.record.channel).to eq(channel)
        expect(result.record.account).to eq(account)
        expect(result.record.category).to eq("sale")
      end
    end
  end

  describe "the movement it writes" do
    let(:payment) { payment_for("cash", amount: 299_700) }

    it "copies the payment's amount as an inflow" do
      result = described_class.call(payment: payment, user: user)

      expect(result.record.amount).to eq(299_700)
      expect(result.record).to be_inflow
    end

    it "links the movement back to the payment" do
      result = described_class.call(payment: payment, user: user)

      expect(result.record.source_payment_id).to eq(payment.id)
    end

    it "takes the business date from the payment, not from today" do
      result = described_class.call(payment: payment, user: user)

      expect(result.record.business_date).to eq(past_day)
      expect(result.record.business_date).not_to eq(Date.current)
    end

    it "stores the description when one is given" do
      result = described_class.call(payment: payment, user: user, description: "Cobro nota de venta #12")

      expect(result.record.description).to eq("Cobro nota de venta #12")
    end

    it "leaves the description empty when none is given" do
      result = described_class.call(payment: payment, user: user)

      expect(result.record.description).to be_nil
    end

    it "records the acting user" do
      result = described_class.call(payment: payment, user: user)

      expect(result.record.user).to eq(user)
    end
  end

  describe "failure" do
    it "refuses a payment that already has a movement" do
      payment = payment_for("cash")

      first = described_class.call(payment: payment, user: user)
      second = described_class.call(payment: payment, user: user)

      expect(first).to be_success
      expect(second).to be_failure
      expect(CashMovement.where(source_payment_id: payment.id).count).to eq(1)
    end

    it "returns a failure instead of raising on an unmapped payment method" do
      payment = payment_for("cash")
      payment.payment_method = "crypto"

      result = nil
      expect { result = described_class.call(payment: payment, user: user) }.not_to raise_error

      expect(result).to be_failure
      expect(CashMovement.count).to eq(0)
    end

    it "rejects a missing payment" do
      result = described_class.call(payment: nil, user: user)

      expect(result).to be_failure
      expect(CashMovement.count).to eq(0)
    end

    it "rejects a missing user" do
      result = described_class.call(payment: payment_for("cash"), user: nil)

      expect(result).to be_failure
      expect(CashMovement.count).to eq(0)
    end
  end
end
