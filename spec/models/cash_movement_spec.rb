# frozen_string_literal: true

require "rails_helper"

RSpec.describe CashMovement, type: :model do
  describe "associations" do
    it { should belong_to(:user) }
    it { should belong_to(:daily_closing).optional }
    it { should belong_to(:source_payment).class_name("Payment").optional }
  end

  describe "validations" do
    it { should validate_presence_of(:business_date) }
    it { should validate_presence_of(:category) }

    it "rejects a zero amount" do
      movement = build(:cash_movement, amount: 0)
      expect(movement).not_to be_valid
      expect(movement.errors[:amount]).to be_present
    end

    it "accepts a negative amount" do
      expect(build(:cash_movement, amount: -13_000)).to be_valid
    end
  end

  describe "enums" do
    it "exposes the six arcas" do
      expect(described_class.accounts.keys).to contain_exactly(
        "drawer", "main_cash", "change_fund", "bank", "mercado_pago", "usd"
      )
    end

    it "exposes the seven categories" do
      expect(described_class.categories.keys).to contain_exactly(
        "sale", "suppliers", "fixed_expense", "internal_transfer",
        "partner", "cash_discrepancy", "opening_balance"
      )
    end

    it "exposes the seven channels" do
      expect(described_class.channels.keys).to contain_exactly(
        "cash", "card", "qr", "transfer", "mercado_pago", "usd", "compensation"
      )
    end

    it "exposes the six fixed-expense subcategories" do
      expect(described_class.subcategories.keys).to contain_exactly(
        "rent", "salaries", "social_charges", "taxes", "utilities", "store_expenses"
      )
    end

    it "suffixes the predicates so account and channel do not collide" do
      movement = build(:cash_movement, account: "mercado_pago", channel: "cash")
      expect(movement.mercado_pago_account?).to be(true)
      expect(movement.cash_channel?).to be(true)
    end
  end

  describe ".account_for_channel" do
    it "routes each channel to its arca" do
      expect(described_class.account_for_channel("cash")).to eq("drawer")
      expect(described_class.account_for_channel("card")).to eq("bank")
      expect(described_class.account_for_channel("qr")).to eq("bank")
      expect(described_class.account_for_channel("transfer")).to eq("bank")
      expect(described_class.account_for_channel("mercado_pago")).to eq("mercado_pago")
      expect(described_class.account_for_channel("usd")).to eq("usd")
    end

    it "routes compensation to no arca at all" do
      expect(described_class.account_for_channel("compensation")).to be_nil
    end

    it "raises on a channel it does not know, rather than reporting no arca" do
      expect { described_class.account_for_channel("bank_card") }.to raise_error(KeyError)
    end

    it "covers every channel the enum accepts" do
      expect(described_class::CHANNEL_ACCOUNTS.keys).to match_array(described_class.channels.keys)
    end
  end

  describe ".channel_for_payment_method" do
    it "maps every payment method to its cash channel" do
      expect(described_class.channel_for_payment_method("cash")).to eq("cash")
      expect(described_class.channel_for_payment_method("bank_qr")).to eq("qr")
      expect(described_class.channel_for_payment_method("bank_card")).to eq("card")
      expect(described_class.channel_for_payment_method("bank_transfer")).to eq("transfer")
      expect(described_class.channel_for_payment_method("mercado_pago")).to eq("mercado_pago")
    end

    it "raises on a payment method it does not know" do
      expect { described_class.channel_for_payment_method("crypto") }.to raise_error(KeyError)
    end

    it "covers every payment method" do
      expect(described_class::PAYMENT_METHOD_CHANNELS.keys).to match_array(Payment::PAYMENT_METHODS)
    end

    it "maps only to channels that have an arca" do
      # key? is not enough: compensation IS a key, mapping to nil. Money that
      # arrives through a payment method always lands somewhere.
      arcas = described_class::PAYMENT_METHOD_CHANNELS.values.map { |channel| described_class::CHANNEL_ACCOUNTS.fetch(channel) }

      expect(arcas).to all(be_present)
    end
  end

  describe "amount column" do
    it "round-trips an opening balance in the tens of millions" do
      movement = create(:cash_movement, :opening_balance)
      expect(movement.reload.amount).to eq(12_497_899.30)
    end
  end

  describe "conditional validations" do
    context "account" do
      it "is required on an ordinary movement" do
        movement = build(:cash_movement, account: nil)
        expect(movement).not_to be_valid
        expect(movement.errors[:base]).to include(
          "Falta el arca: indicá a qué caja entra o de cuál sale el dinero."
        )
      end

      it "must be absent on a compensation sale" do
        expect(build(:cash_movement, :compensation_sale)).to be_valid
      end

      it "is rejected when a compensation sale names an arca" do
        movement = build(:cash_movement, :compensation_sale, account: "bank")
        expect(movement).not_to be_valid
        expect(movement.errors[:base]).to include(
          "Una venta por compensación no lleva arca: no entra dinero a ninguna caja."
        )
      end
    end

    context "channel" do
      it "is required on a sale" do
        movement = build(:cash_movement, category: "sale", channel: nil)
        expect(movement).not_to be_valid
        expect(movement.errors[:base]).to include(
          "Falta el canal: indicá cómo entró el dinero de la venta."
        )
      end

      it "must be absent on anything that is not a sale" do
        movement = build(:cash_movement, :supplier_payment, channel: "cash")
        expect(movement).not_to be_valid
        expect(movement.errors[:base]).to include(
          "El canal solo corresponde a una venta."
        )
      end
    end

    context "subcategory" do
      it "is required on a fixed expense" do
        movement = build(:cash_movement, :store_expense, subcategory: nil)
        expect(movement).not_to be_valid
        expect(movement.errors[:base]).to include(
          "Falta la subcategoría: indicá de qué tipo de gasto fijo se trata."
        )
      end

      it "must be absent on anything that is not a fixed expense" do
        movement = build(:cash_movement, :supplier_payment, subcategory: "rent")
        expect(movement).not_to be_valid
        expect(movement.errors[:base]).to include(
          "La subcategoría solo corresponde a un gasto fijo."
        )
      end
    end

    context "supplier" do
      it "is required on a compensation sale" do
        movement = build(:cash_movement, :compensation_sale, supplier: nil)
        expect(movement).not_to be_valid
        expect(movement.errors[:base]).to include(
          "Falta el proveedor: indicá a quién se le descuenta la deuda por la compensación."
        )
      end

      it "is accepted on a compensation sale" do
        movement = build(:cash_movement, :compensation_sale)
        expect(movement.supplier).to be_present
        expect(movement).to be_valid
      end

      it "must be absent on anything that is not a compensation sale" do
        movement = build(:cash_movement, supplier: build(:supplier))
        expect(movement).not_to be_valid
        expect(movement.errors[:base]).to include(
          "El proveedor solo corresponde a una venta por compensación."
        )
      end
    end
  end

  describe "balances" do
    let(:day) { Date.new(2026, 8, 3) }

    before do
      create(:cash_movement, business_date: day, account: "drawer", amount: 299_700)
      create(:cash_movement, business_date: day, account: "drawer", amount: 25_000)
      create(:cash_movement, :store_expense, business_date: day, amount: -13_000)
      create(:cash_movement, :card_sale, business_date: day)
      create(:cash_movement, business_date: day + 1.day, account: "drawer", amount: 100_000)
    end

    it "sums a single arca across every date" do
      expect(described_class.balance_for("drawer")).to eq(411_700)
    end

    it "sums a single arca on one date" do
      expect(described_class.drawer_balance_on(day)).to eq(311_700)
    end

    it "keeps the arcas separate" do
      expect(described_class.balance_for("bank")).to eq(54_700)
    end

    it "returns zero for an arca with no movements" do
      expect(described_class.balance_for("usd")).to eq(0)
    end

    it "ignores a compensation sale, which touches no arca" do
      create(:cash_movement, :compensation_sale, business_date: day)
      expect(described_class.drawer_balance_on(day)).to eq(311_700)
      expect(described_class.where(account: nil).count).to eq(1)
    end
  end

  describe "scopes" do
    let(:day) { Date.new(2026, 8, 3) }

    before do
      create(:cash_movement, business_date: day - 1.day)
      create(:cash_movement, business_date: day)
      create(:cash_movement, business_date: day + 1.day)
      create(:cash_movement, business_date: day + 2.days)
      create(:cash_movement, :store_expense, business_date: day)
    end

    describe ".between" do
      it "includes both ends of the range" do
        expect(described_class.between(day - 1.day, day + 1.day).count).to eq(4)
      end

      it "excludes what falls outside it" do
        dates = described_class.between(day, day).pluck(:business_date).uniq
        expect(dates).to eq([ day ])
      end

      it "returns nothing for a range with no movements" do
        expect(described_class.between(day + 10.days, day + 20.days)).to be_empty
      end
    end

    describe ".sales" do
      it "keeps only sale movements" do
        expect(described_class.sales.count).to eq(4)
        expect(described_class.sales.pluck(:category).uniq).to eq([ "sale" ])
      end

      it "composes with a date scope" do
        expect(described_class.sales.on(day).count).to eq(1)
      end
    end
  end

  describe "immutability once sealed" do
    it "is not sealed while daily_closing_id is blank" do
      expect(create(:cash_movement)).not_to be_sealed
    end

    it "allows the closing to stamp an unsealed movement" do
      movement = create(:cash_movement)
      closing = create(:daily_closing, business_date: movement.business_date)

      expect { movement.update!(daily_closing: closing) }.not_to raise_error
      expect(movement.reload).to be_sealed
    end

    it "refuses any later update" do
      movement = create(:cash_movement, :sealed)
      expect { movement.update!(amount: 1) }
        .to raise_error(described_class::SealedMovementError)
    end

    it "refuses destruction" do
      movement = create(:cash_movement, :sealed)
      expect { movement.destroy }
        .to raise_error(described_class::SealedMovementError)
    end

    it "leaves the row untouched after a refused update" do
      movement = create(:cash_movement, :sealed, amount: 299_700)
      expect { movement.update!(amount: 1) }.to raise_error(described_class::SealedMovementError)
      expect(movement.reload.amount).to eq(299_700)
    end

    it "seals the movement under a closing of its own business date" do
      movement = create(:cash_movement, :sealed)
      expect(movement.daily_closing.business_date).to eq(movement.business_date)
    end
  end

  describe "#paper_numbers" do
    let(:customer) { create(:customer, :with_credit) }
    let(:payment)  { create(:payment, customer: customer, amount: 300) }

    it "lists every note the source payment settled, in order" do
      %w[0042 0007].each do |paper|
        order = create(:order, customer: customer, paper_number: paper, total_amount: 100)
        create(:payment_allocation, payment: payment, order: order, amount: 100)
      end

      movement = create(:cash_movement, source_payment: payment)

      expect(movement.paper_numbers).to eq([ "0007", "0042" ])
    end

    it "lists the single note of a one-note collection" do
      order = create(:order, customer: customer, paper_number: "0042", total_amount: 100)
      create(:payment_allocation, payment: payment, order: order, amount: 100)

      movement = create(:cash_movement, source_payment: payment)

      expect(movement.paper_numbers).to eq([ "0042" ])
    end

    it "is empty on a row the cashier typed, which has no payment behind it" do
      expect(create(:cash_movement).paper_numbers).to eq([])
    end
  end

  describe "#transfer?" do
    it "is true on one leg of a Cash::RecordTransfer pair" do
      expect(build(:cash_movement, :transfer_leg)).to be_transfer
    end

    it "is false on a row with no transfer_group_id" do
      expect(build(:cash_movement)).not_to be_transfer
    end
  end

  describe "#transfer_counterpart_label" do
    let(:transfer_user) { create(:user, :caja) }

    def legs(from: "drawer", to: "bank")
      ::Cash::RecordTransfer.call(
        from: from, to: to, amount: 80_000,
        business_date: Date.new(2026, 8, 3), user: transfer_user
      ).record
    end

    it "says where the money went on the leg that lost it" do
      outflow, = legs

      expect(outflow.transfer_counterpart_label).to eq("hacia Banco")
    end

    it "says where the money came from on the leg that gained it" do
      _, inflow = legs

      expect(inflow.transfer_counterpart_label).to eq("desde Caja del día")
    end

    it "uses the fine arca, not the reporting group" do
      outflow, = legs(from: "main_cash", to: "change_fund")

      expect(outflow.transfer_counterpart_label).to eq("hacia Remanente")
    end

    it "is nil on a row that is not a transfer" do
      expect(create(:cash_movement).transfer_counterpart_label).to be_nil
    end

    it "is nil on a leg whose twin is gone" do
      outflow, inflow = legs
      inflow.destroy!

      expect(outflow.reload.transfer_counterpart_label).to be_nil
    end
  end

  describe "reporting groups" do
    it "puts every arca in exactly one group, and only real arcas in a group" do
      grouped_accounts = described_class::REPORTING_GROUPS.values.flatten
      expect(grouped_accounts).to match_array(described_class::ACCOUNT_LABELS.keys)
    end

    it "groups Efectivo as exactly the three cash arcas" do
      expect(described_class::REPORTING_GROUPS.fetch("efectivo")).to contain_exactly(
        "drawer", "main_cash", "change_fund"
      )
    end

    describe ".reporting_group_for" do
      it "maps each arca to its group" do
        expect(described_class.reporting_group_for("drawer")).to eq("efectivo")
        expect(described_class.reporting_group_for("main_cash")).to eq("efectivo")
        expect(described_class.reporting_group_for("change_fund")).to eq("efectivo")
        expect(described_class.reporting_group_for("bank")).to eq("banco")
        expect(described_class.reporting_group_for("mercado_pago")).to eq("mercado_pago")
        expect(described_class.reporting_group_for("usd")).to eq("usd")
      end

      it "raises on an arca it does not know, rather than reporting no group" do
        expect { described_class.reporting_group_for("crypto") }.to raise_error(KeyError)
      end
    end
  end
end
