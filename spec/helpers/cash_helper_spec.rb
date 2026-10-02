# frozen_string_literal: true

require "rails_helper"

RSpec.describe CashHelper, type: :helper do
  describe "#cash_entry_invoice" do
    let(:payment) { create(:payment, payment_method: "mercado_pago") }

    it "shows type and number of a billed collection" do
      payment.update!(invoice_type: "b", invoice_number: "1452")

      expect(helper.cash_entry_invoice(build(:cash_movement, source_payment: payment))).to eq("B · 1452")
    end

    it "shows S/F for a collection with no invoice" do
      payment.update!(invoice_type: "none")

      expect(helper.cash_entry_invoice(build(:cash_movement, source_payment: payment))).to eq("S/F")
    end

    it "is nil for an unbilled collection, so the row offers to invoice it" do
      expect(helper.cash_entry_invoice(build(:cash_movement, source_payment: payment))).to be_nil
    end

    it "is a dash for rows with no collection and for reversals" do
      expect(helper.cash_entry_invoice(build(:cash_movement, :store_expense))).to eq("—")
      expect(helper.cash_entry_invoice(build(:cash_movement, source_payment: payment, amount: -1_000))).to eq("—")
    end

    it "is a dash on the original row of a collection that was later reversed" do
      original = create(:cash_movement, source_payment: payment, business_date: Date.current, amount: 1_000)
      create(:cash_movement, source_payment: payment, business_date: Date.current, amount: -1_000)

      expect(helper.cash_entry_invoice(original.reload)).to eq("—")
    end
  end
end
