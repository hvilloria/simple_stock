require "rails_helper"

RSpec.describe Supplier, type: :model do
  describe "associations" do
    it { is_expected.to have_many(:invoices).dependent(:restrict_with_error) }
    it { is_expected.to have_many(:credit_notes).dependent(:restrict_with_error) }
  end

  describe "validations" do
    subject { build(:supplier) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:name).case_insensitive }

    it "validates email format" do
      supplier = build(:supplier, email: "invalid-email")
      expect(supplier).not_to be_valid
      expect(supplier.errors[:email]).to be_present
    end

    it "allows blank email" do
      supplier = build(:supplier, email: nil)
      expect(supplier).to be_valid
    end

    it "validates payment_term_days is positive integer" do
      supplier = build(:supplier, payment_term_days: -5)
      expect(supplier).not_to be_valid
    end

    it "allows nil payment_term_days" do
      supplier = build(:supplier, payment_term_days: nil)
      expect(supplier).to be_valid
    end
  end

  describe "#bank_info_present?" do
    it "returns true if bank_alias present" do
      supplier = build(:supplier, bank_alias: "MI.ALIAS", bank_account: nil)
      expect(supplier.bank_info_present?).to be true
    end

    it "returns true if bank_account present" do
      supplier = build(:supplier, bank_alias: nil, bank_account: "0170000040000012345678")
      expect(supplier.bank_info_present?).to be true
    end

    it "returns false if both blank" do
      supplier = build(:supplier, bank_alias: nil, bank_account: nil)
      expect(supplier.bank_info_present?).to be false
    end
  end

  describe "#payment_term_display" do
    it "returns formatted days" do
      supplier = build(:supplier, payment_term_days: 30)
      expect(supplier.payment_term_display).to eq("30 días")
    end

    it "returns \"No definido\" if nil" do
      supplier = build(:supplier, payment_term_days: nil)
      expect(supplier.payment_term_display).to eq("No definido")
    end
  end

  describe "#total_pending_amount" do
    let(:supplier) { create(:supplier) }

    it "sums pending invoices in ARS" do
      create(:invoice, :simple_mode, supplier: supplier, amount: 1000, currency: "USD", exchange_rate: 1200, status: "pending")
      create(:invoice, :simple_mode, supplier: supplier, amount: 500000, currency: "ARS", status: "pending")
      create(:invoice, :simple_mode, supplier: supplier, amount: 500, currency: "USD", exchange_rate: 1200, status: "paid")

      # 1000 * 1200 + 500000 = 1,700,000
      expect(supplier.total_pending_amount).to eq(1_700_000)
    end
  end

  describe "#total_credit_notes_amount" do
    let(:supplier) { create(:supplier) }

    it "sums all credit notes in ARS" do
      create(:credit_note, supplier: supplier, amount: 500, currency: "USD", exchange_rate: 1200)
      create(:credit_note, supplier: supplier, amount: 100000, currency: "ARS")

      # 500 * 1200 + 100000 = 700,000
      expect(supplier.total_credit_notes_amount).to eq(700_000)
    end

    it "returns 0 when no credit notes" do
      expect(supplier.total_credit_notes_amount).to eq(0)
    end
  end

  describe "#credit_notes_count" do
    let(:supplier) { create(:supplier) }

    it "returns count of credit notes" do
      create(:credit_note, supplier: supplier)
      create(:credit_note, supplier: supplier)

      expect(supplier.credit_notes_count).to eq(2)
    end
  end

  describe "#current_balance" do
    let(:supplier) { create(:supplier) }

    it "calculates balance as pending_amount minus credit_notes" do
      create(:invoice, :simple_mode, supplier: supplier, amount: 1000, currency: "USD", exchange_rate: 1200, status: "pending")
      create(:credit_note, supplier: supplier, amount: 500, currency: "USD", exchange_rate: 1200)

      # Pending: 1000 * 1200 = 1,200,000
      # Credit: 500 * 1200 = 600,000
      # Balance: 1,200,000 - 600,000 = 600,000
      expect(supplier.current_balance).to eq(600_000)
    end

    it "returns negative balance if credits exceed pending" do
      create(:invoice, :simple_mode, supplier: supplier, amount: 500, currency: "USD", exchange_rate: 1200, status: "pending")
      create(:credit_note, supplier: supplier, amount: 1000, currency: "USD", exchange_rate: 1200)

      # Pending: 500 * 1200 = 600,000
      # Credit: 1000 * 1200 = 1,200,000
      # Balance: 600,000 - 1,200,000 = -600,000
      expect(supplier.current_balance).to eq(-600_000)
    end
  end
end
