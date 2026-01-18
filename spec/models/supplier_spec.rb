require "rails_helper"

RSpec.describe Supplier, type: :model do
  describe "associations" do
    it { is_expected.to have_many(:purchases).dependent(:restrict_with_error) }
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

    it "sums pending purchases in ARS" do
      create(:purchase, :simple_mode, supplier: supplier, amount: 1000, currency: "USD", exchange_rate: 1200, status: "pending")
      create(:purchase, :simple_mode, supplier: supplier, amount: 500000, currency: "ARS", status: "pending")
      create(:purchase, :simple_mode, supplier: supplier, amount: 500, currency: "USD", exchange_rate: 1200, status: "paid")

      # 1000 * 1200 + 500000 = 1,700,000
      expect(supplier.total_pending_amount).to eq(1_700_000)
    end
  end
end
