require "rails_helper"

RSpec.describe Purchase, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:supplier) }
    it { is_expected.to have_many(:purchase_items).dependent(:destroy) }
    it { is_expected.to have_many(:products).through(:purchase_items) }
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:status).with_values(pending: "pending", paid: "paid", confirmed: "confirmed", cancelled: "cancelled").backed_by_column_of_type(:string).with_suffix }
  end

  describe "validations" do
    it { is_expected.to validate_inclusion_of(:currency).in_array(%w[USD ARS]) }

    context "when currency is USD" do
      subject { build(:purchase, currency: "USD") }

      it { is_expected.to validate_presence_of(:exchange_rate) }
      it { is_expected.to validate_numericality_of(:exchange_rate).is_greater_than(0) }
    end

    context "when currency is ARS" do
      subject { build(:purchase, :in_ars) }

      it "does not require exchange_rate" do
        purchase = build(:purchase, :in_ars, exchange_rate: nil)
        purchase.valid? # Trigger validations to see actual errors
        expect(purchase.errors[:exchange_rate]).to be_empty
      end
    end

    it { is_expected.to validate_presence_of(:purchase_date) }
  end

  describe "#calculate_total" do
    it "calculates total from purchase items" do
      purchase = create(:purchase)
      # Limpiar items por defecto
      purchase.purchase_items.destroy_all
      create(:purchase_item, purchase: purchase, quantity: 5, unit_cost: 10)
      create(:purchase_item, purchase: purchase, quantity: 3, unit_cost: 20)

      expect(purchase.reload.calculate_total).to eq(110) # (5*10) + (3*20)
    end

    it "returns 0 when there are no items" do
      purchase = create(:purchase)
      purchase.purchase_items.destroy_all
      expect(purchase.reload.calculate_total).to eq(0)
    end
  end

  describe "#calculate_total_ars" do
    context "when currency is USD" do
      it "converts total to ARS using exchange rate" do
        purchase = create(:purchase, currency: "USD", exchange_rate: 1200)
        purchase.purchase_items.destroy_all
        create(:purchase_item, purchase: purchase, quantity: 10, unit_cost: 50)

        # Total: 10 * 50 = 500 USD
        # In ARS: 500 * 1200 = 600000
        expect(purchase.reload.calculate_total_ars).to eq(600000)
      end
    end

    context "when currency is ARS" do
      it "returns total without conversion" do
        purchase = create(:purchase, :in_ars)
        purchase.purchase_items.destroy_all
        create(:purchase_item, purchase: purchase, quantity: 10, unit_cost: 5000)

        # Total: 10 * 5000 = 50000 ARS
        expect(purchase.reload.calculate_total_ars).to eq(50000)
      end
    end
  end

  # === TESTS PARA MODO SIMPLE ===

  describe "validations for simple mode" do
    subject { build(:purchase, :simple_mode) }

    it { is_expected.to validate_presence_of(:invoice_number) }
    it { is_expected.to validate_presence_of(:due_date) }
    it { is_expected.to validate_presence_of(:amount) }
    
    it "validates amount is greater than 0" do
      purchase = build(:purchase, :simple_mode, amount: 0)
      expect(purchase).not_to be_valid
      expect(purchase.errors[:amount]).to be_present
    end
  end

  describe "validations for full mode" do
    it "requires purchase_items on update" do
      purchase = create(:purchase, has_items: true, status: "confirmed")
      purchase.purchase_items.clear
      purchase.valid?(:update)
      expect(purchase.errors[:purchase_items]).to be_present
    end
  end

  describe "#simple_mode?" do
    it "returns true for purchases without items" do
      purchase = build(:purchase, :simple_mode)
      expect(purchase.simple_mode?).to be true
    end

    it "returns false for purchases with items" do
      purchase = build(:purchase, :full_mode)
      expect(purchase.simple_mode?).to be false
    end
  end

  describe "#full_mode?" do
    it "returns true for purchases with items" do
      purchase = build(:purchase, :full_mode)
      expect(purchase.full_mode?).to be true
    end

    it "returns false for purchases without items" do
      purchase = build(:purchase, :simple_mode)
      expect(purchase.full_mode?).to be false
    end
  end

  describe "#total_amount" do
    context "in simple mode" do
      it "returns the amount field" do
        purchase = build(:purchase, :simple_mode, amount: 5000)
        expect(purchase.total_amount).to eq(5000)
      end
    end

    context "in full mode" do
      it "calculates from purchase_items" do
        purchase = create(:purchase, :full_mode)
        purchase.purchase_items.destroy_all
        create(:purchase_item, purchase: purchase, quantity: 10, unit_cost: 50)
        
        expect(purchase.reload.total_amount).to eq(500)
      end
    end
  end

  describe "#total_amount_ars" do
    it "converts USD to ARS using exchange_rate" do
      purchase = build(:purchase, :simple_mode, 
                      amount: 1000, 
                      currency: "USD", 
                      exchange_rate: 1200)
      
      expect(purchase.total_amount_ars).to eq(1_200_000)
    end

    it "returns amount directly for ARS" do
      purchase = build(:purchase, :simple_mode, 
                      amount: 500_000, 
                      currency: "ARS",
                      exchange_rate: nil)
      
      expect(purchase.total_amount_ars).to eq(500_000)
    end
  end

  describe "#overdue?" do
    it "returns true for pending purchases past due date" do
      purchase = create(:purchase, :simple_mode, 
                       status: "pending",
                       due_date: 1.day.ago)
      
      expect(purchase.overdue?).to be true
    end

    it "returns false for pending purchases not yet due" do
      purchase = create(:purchase, :simple_mode, 
                       status: "pending",
                       due_date: 1.day.from_now)
      
      expect(purchase.overdue?).to be false
    end

    it "returns false for paid purchases" do
      purchase = create(:purchase, :simple_mode, 
                       status: "paid",
                       due_date: 1.day.ago)
      
      expect(purchase.overdue?).to be false
    end
  end

  describe "#days_until_due" do
    it "returns positive days for future due date" do
      purchase = build(:purchase, :simple_mode, due_date: 5.days.from_now.to_date)
      expect(purchase.days_until_due).to eq(5)
    end

    it "returns negative days for past due date" do
      purchase = build(:purchase, :simple_mode, due_date: 3.days.ago.to_date)
      expect(purchase.days_until_due).to eq(-3)
    end

    it "returns nil when due_date is not set" do
      purchase = build(:purchase, :full_mode)
      expect(purchase.days_until_due).to be_nil
    end
  end

  describe "#mark_as_paid!" do
    let(:purchase) { create(:purchase, :simple_mode, status: "pending") }

    it "updates status to paid" do
      purchase.mark_as_paid!
      expect(purchase.reload.paid_status?).to be true
    end

    it "records payment date" do
      payment_date = Date.yesterday
      purchase.mark_as_paid!(payment_date)
      
      expect(purchase.reload.paid_at.to_date).to eq(payment_date)
    end

    it "raises error if not simple mode" do
      full_purchase = create(:purchase, :full_mode)
      
      expect {
        full_purchase.mark_as_paid!
      }.to raise_error("Cannot mark as paid: not in simple mode")
    end

    it "raises error if already paid" do
      purchase.mark_as_paid!
      
      expect {
        purchase.mark_as_paid!
      }.to raise_error("Cannot mark as paid: already paid")
    end
  end

  describe "scopes" do
    let!(:simple_pending) { create(:purchase, :simple_mode, status: "pending", due_date: 5.days.from_now) }
    let!(:simple_overdue) { create(:purchase, :simple_mode, status: "pending", due_date: 1.day.ago) }
    let!(:simple_paid) { create(:purchase, :simple_mode, status: "paid") }
    let!(:full_purchase) { create(:purchase, :full_mode) }

    describe ".simple_mode" do
      it "returns only simple mode purchases" do
        expect(Purchase.simple_mode).to include(simple_pending, simple_overdue, simple_paid)
        expect(Purchase.simple_mode).not_to include(full_purchase)
      end
    end

    describe ".full_mode" do
      it "returns only full mode purchases" do
        expect(Purchase.full_mode).to include(full_purchase)
        expect(Purchase.full_mode).not_to include(simple_pending)
      end
    end

    describe ".pending_payment" do
      it "returns only pending purchases" do
        expect(Purchase.pending_payment).to include(simple_pending, simple_overdue)
        expect(Purchase.pending_payment).not_to include(simple_paid, full_purchase)
      end
    end

    describe ".overdue" do
      it "returns only overdue purchases" do
        expect(Purchase.overdue).to include(simple_overdue)
        expect(Purchase.overdue).not_to include(simple_pending, simple_paid)
      end
    end

    describe ".due_soon" do
      it "returns purchases due within 7 days" do
        expect(Purchase.due_soon).to include(simple_pending, simple_overdue)
      end
    end

    describe ".due_today" do
      let!(:due_today) { create(:purchase, :simple_mode, status: "pending", due_date: Date.current) }
      let!(:due_tomorrow) { create(:purchase, :simple_mode, status: "pending", due_date: Date.current + 1.day) }

      it "returns only purchases due today" do
        expect(Purchase.due_today).to include(due_today)
        expect(Purchase.due_today).not_to include(due_tomorrow)
      end
    end

    describe ".due_this_week" do
      let!(:due_monday) { create(:purchase, :simple_mode, status: "pending", due_date: Date.current.beginning_of_week(:monday)) }
      let!(:due_friday) { create(:purchase, :simple_mode, status: "pending", due_date: Date.current.end_of_week(:monday) - 2.days) }
      let!(:due_next_week) { create(:purchase, :simple_mode, status: "pending", due_date: Date.current.end_of_week(:monday) + 1.day) }

      it "returns purchases due this week (monday to sunday)" do
        expect(Purchase.due_this_week).to include(due_monday, due_friday)
        expect(Purchase.due_this_week).not_to include(due_next_week)
      end
    end
  end
end
