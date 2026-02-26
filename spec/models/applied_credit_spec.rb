require "rails_helper"

RSpec.describe AppliedCredit, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:credit_note) }
    it { is_expected.to belong_to(:invoice) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:amount) }
    it { is_expected.to validate_numericality_of(:amount).is_greater_than(0) }
    it { is_expected.to validate_presence_of(:applied_at) }
  end

  describe "custom validations" do
    let(:supplier) { create(:supplier) }
    let(:credit_note) { create(:credit_note, supplier: supplier, amount: 50_000) }
    let(:invoice) { create(:invoice, :simple_mode, supplier: supplier) }

    describe "#amount_within_remaining_balance" do
      it "is valid when amount is within remaining balance" do
        applied_credit = build(:applied_credit, credit_note: credit_note, invoice: invoice, amount: 30_000)
        expect(applied_credit).to be_valid
      end

      it "is invalid when amount exceeds remaining balance" do
        applied_credit = build(:applied_credit, credit_note: credit_note, invoice: invoice, amount: 60_000)
        expect(applied_credit).not_to be_valid
        expect(applied_credit.errors[:amount]).to be_present
      end

      it "accounts for previously applied amounts" do
        create(:applied_credit, credit_note: credit_note, invoice: invoice, amount: 40_000, applied_at: Date.today)

        second_application = build(:applied_credit, credit_note: credit_note, invoice: invoice, amount: 20_000)
        expect(second_application).not_to be_valid
      end

      it "allows applying exactly the remaining balance" do
        create(:applied_credit, credit_note: credit_note, invoice: invoice, amount: 30_000, applied_at: Date.today)

        second_application = build(:applied_credit, credit_note: credit_note, invoice: invoice, amount: 20_000)
        expect(second_application).to be_valid
      end

      it "excludes self when updating (avoids false validation on update)" do
        applied = create(:applied_credit, credit_note: credit_note, invoice: invoice, amount: 50_000, applied_at: Date.today)
        applied.amount = 50_000
        expect(applied).to be_valid
      end
    end

    describe "#same_supplier" do
      it "is valid when credit note and invoice share the same supplier" do
        applied_credit = build(:applied_credit, credit_note: credit_note, invoice: invoice)
        expect(applied_credit).to be_valid
      end

      it "is invalid when credit note and invoice belong to different suppliers" do
        other_supplier = create(:supplier)
        other_invoice = create(:invoice, :simple_mode, supplier: other_supplier)

        applied_credit = build(:applied_credit, credit_note: credit_note, invoice: other_invoice)
        expect(applied_credit).not_to be_valid
        expect(applied_credit.errors[:base]).to include(
          match(/mismo proveedor/i)
        )
      end
    end
  end
end
