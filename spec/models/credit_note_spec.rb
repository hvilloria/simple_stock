require "rails_helper"

RSpec.describe CreditNote, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:supplier) }
    it { is_expected.to belong_to(:invoice).optional }
    it { is_expected.to have_many(:credit_note_items) }
    it { is_expected.to have_many(:products) }
    it { is_expected.to have_many(:applied_credits) }
  end

  describe "validations" do
    subject { build(:credit_note) }

    it { is_expected.to validate_presence_of(:credit_note_number) }
    it { is_expected.to validate_uniqueness_of(:credit_note_number) }
    it { is_expected.to validate_presence_of(:amount) }
    it { is_expected.to validate_numericality_of(:amount).is_greater_than(0) }
    it { is_expected.to validate_inclusion_of(:currency).in_array(%w[USD ARS]) }
    it { is_expected.to validate_presence_of(:issue_date) }
    it { is_expected.to validate_presence_of(:supplier_id) }

    context "when currency is USD" do
      subject { build(:credit_note, :usd) }
      it { is_expected.to validate_presence_of(:exchange_rate) }
      it { is_expected.to validate_numericality_of(:exchange_rate).is_greater_than(0) }
    end

    context "when currency is ARS" do
      subject { build(:credit_note, :ars) }
      it { is_expected.not_to validate_presence_of(:exchange_rate) }
    end
  end

  describe "enum status" do
    it "has active and cancelled statuses" do
      expect(CreditNote.statuses).to eq("active" => "active", "cancelled" => "cancelled")
    end

    it "defaults to active" do
      credit_note = create(:credit_note)
      expect(credit_note.active_status?).to be true
    end

    it "defaults status to active when not explicitly set" do
      supplier = create(:supplier)
      credit_note = CreditNote.new(
        credit_note_number: "NCC-REG-001",
        amount: 500,
        currency: "ARS",
        issue_date: Date.current,
        supplier: supplier
      )

      expect(credit_note.status).to eq("active")
      expect { credit_note.save! }.not_to raise_error
    end
  end

  describe "#total_amount_ars" do
    context "when currency is USD" do
      it "converts amount to ARS using exchange rate" do
        credit_note = build(:credit_note, amount: 100, currency: "USD", exchange_rate: 1200)
        expect(credit_note.total_amount_ars).to eq(120_000)
      end

      it "returns 0 when exchange_rate is nil" do
        credit_note = build(:credit_note, amount: 100, currency: "USD", exchange_rate: nil)
        expect(credit_note.total_amount_ars).to eq(0)
      end
    end

    context "when currency is ARS" do
      it "returns amount without conversion" do
        credit_note = build(:credit_note, amount: 5000, currency: "ARS")
        expect(credit_note.total_amount_ars).to eq(5000)
      end
    end
  end

  describe "#remaining_balance" do
    it "returns full amount when no credits have been applied" do
      credit_note = create(:credit_note, amount: 50_000)
      expect(credit_note.remaining_balance).to eq(50_000)
    end

    it "subtracts applied amounts from the total" do
      credit_note = create(:credit_note, amount: 50_000)
      invoice = create(:invoice, :simple_mode, supplier: credit_note.supplier)
      create(:applied_credit, credit_note: credit_note, invoice: invoice, amount: 10_000, applied_at: Date.today)

      expect(credit_note.remaining_balance).to eq(40_000)
    end

    it "returns 0 when fully applied across multiple invoices" do
      credit_note = create(:credit_note, amount: 50_000)
      invoice1 = create(:invoice, :simple_mode, supplier: credit_note.supplier)
      invoice2 = create(:invoice, :simple_mode, supplier: credit_note.supplier)
      create(:applied_credit, credit_note: credit_note, invoice: invoice1, amount: 30_000, applied_at: Date.today)
      create(:applied_credit, credit_note: credit_note, invoice: invoice2, amount: 20_000, applied_at: Date.today)

      expect(credit_note.remaining_balance).to eq(0)
    end
  end

  describe "#exhausted?" do
    it "returns false when balance is available" do
      credit_note = create(:credit_note, amount: 50_000)
      expect(credit_note.exhausted?).to be false
    end

    it "returns true when fully applied" do
      credit_note = create(:credit_note, amount: 50_000)
      invoice = create(:invoice, :simple_mode, supplier: credit_note.supplier)
      create(:applied_credit, credit_note: credit_note, invoice: invoice, amount: 50_000, applied_at: Date.today)

      expect(credit_note.exhausted?).to be true
    end
  end

  describe "#available?" do
    it "returns true when active and has remaining balance" do
      credit_note = create(:credit_note, amount: 50_000)
      expect(credit_note.available?).to be true
    end

    it "returns false when cancelled" do
      credit_note = create(:credit_note, status: "cancelled")
      expect(credit_note.available?).to be false
    end

    it "returns false when active but exhausted" do
      credit_note = create(:credit_note, amount: 50_000)
      invoice = create(:invoice, :simple_mode, supplier: credit_note.supplier)
      create(:applied_credit, credit_note: credit_note, invoice: invoice, amount: 50_000, applied_at: Date.today)

      expect(credit_note.available?).to be false
    end
  end

  describe "#remaining_balance_ars" do
    it "returns remaining balance for ARS credit notes" do
      credit_note = create(:credit_note, amount: 50_000, currency: "ARS")
      invoice = create(:invoice, :simple_mode, supplier: credit_note.supplier)
      create(:applied_credit, credit_note: credit_note, invoice: invoice, amount: 10_000, applied_at: Date.today)

      expect(credit_note.remaining_balance_ars).to eq(40_000)
    end
  end

  describe "#has_items?" do
    it "returns false when there are no items" do
      credit_note = create(:credit_note)
      expect(credit_note.has_items?).to be false
    end

    it "returns true when there are items" do
      credit_note = create(:credit_note)
      create(:credit_note_item, credit_note: credit_note)
      expect(credit_note.has_items?).to be true
    end
  end

  describe "callbacks" do
    describe "#set_currency_from_invoice" do
      let(:invoice) { create(:invoice, :simple_mode, currency: "USD", exchange_rate: 1300) }

      it "inherits currency from invoice" do
        credit_note = CreditNote.new(
          supplier: invoice.supplier,
          invoice: invoice,
          credit_note_number: "NC-001",
          amount: 100,
          issue_date: Date.today
        )

        credit_note.valid?

        expect(credit_note.currency).to eq("USD")
        expect(credit_note.exchange_rate).to eq(1300)
      end

      it "does not override manually set currency if invoice is not changed" do
        credit_note = create(:credit_note, invoice: invoice, currency: "USD", exchange_rate: 1300)
        credit_note.amount = 200
        credit_note.save

        expect(credit_note.currency).to eq("USD")
        expect(credit_note.exchange_rate).to eq(1300)
      end
    end
  end

  describe "scopes" do
    describe ".available" do
      it "returns active credit notes" do
        active = create(:credit_note, status: "active")
        create(:credit_note, status: "cancelled")

        expect(CreditNote.available).to contain_exactly(active)
      end
    end

    describe ".for_supplier" do
      let(:supplier1) { create(:supplier) }
      let(:supplier2) { create(:supplier) }

      before do
        create(:credit_note, supplier: supplier1, credit_note_number: "NC-001")
        create(:credit_note, supplier: supplier1, credit_note_number: "NC-002")
        create(:credit_note, supplier: supplier2, credit_note_number: "NC-003")
      end

      it "returns credit notes for specific supplier" do
        result = CreditNote.for_supplier(supplier1)
        expect(result.count).to eq(2)
        expect(result.pluck(:credit_note_number)).to match_array([ "NC-001", "NC-002" ])
      end

      it "returns all when supplier is nil" do
        result = CreditNote.for_supplier(nil)
        expect(result.count).to eq(3)
      end
    end

    describe ".search_number" do
      before do
        create(:credit_note, credit_note_number: "NC-001")
        create(:credit_note, credit_note_number: "NC-002")
        create(:credit_note, credit_note_number: "FAC-123")
      end

      it "finds credit notes by partial number match" do
        result = CreditNote.search_number("NC-")
        expect(result.count).to eq(2)
      end

      it "is case insensitive" do
        result = CreditNote.search_number("nc-001")
        expect(result.count).to eq(1)
      end

      it "returns all when query is blank" do
        result = CreditNote.search_number(nil)
        expect(result.count).to eq(3)
      end
    end

    describe ".recent" do
      let!(:cn1) { create(:credit_note, issue_date: 3.days.ago) }
      let!(:cn2) { create(:credit_note, issue_date: 1.day.ago) }
      let!(:cn3) { create(:credit_note, issue_date: 2.days.ago) }

      it "orders by issue_date descending, then created_at descending" do
        result = CreditNote.recent.pluck(:id)
        expect(result).to eq([ cn2.id, cn3.id, cn1.id ])
      end
    end
  end
end
