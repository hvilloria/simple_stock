require "rails_helper"

RSpec.describe Invoice, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:supplier) }
    it { is_expected.to have_many(:invoice_items).dependent(:destroy) }
    it { is_expected.to have_many(:products).through(:invoice_items) }
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:status).with_values(pending: "pending", paid: "paid", confirmed: "confirmed", cancelled: "cancelled").backed_by_column_of_type(:string).with_suffix }
  end

  describe "validations" do
    it { is_expected.to validate_inclusion_of(:currency).in_array(%w[USD ARS]) }

    context "when currency is USD" do
      subject { build(:invoice, currency: "USD") }

      it { is_expected.to validate_presence_of(:exchange_rate) }
      it { is_expected.to validate_numericality_of(:exchange_rate).is_greater_than(0) }
    end

    context "when currency is ARS" do
      subject { build(:invoice, :in_ars) }

      it "does not require exchange_rate" do
        invoice = build(:invoice, :in_ars, exchange_rate: nil)
        invoice.valid? # Trigger validations to see actual errors
        expect(invoice.errors[:exchange_rate]).to be_empty
      end
    end

    it { is_expected.to validate_presence_of(:purchase_date) }
  end

  describe "#calculate_total" do
    it "calculates total from invoice items" do
      invoice = create(:invoice)
      # Clear default items
      invoice.invoice_items.destroy_all
      create(:invoice_item, invoice: invoice, quantity: 5, unit_cost: 10)
      create(:invoice_item, invoice: invoice, quantity: 3, unit_cost: 20)

      expect(invoice.reload.calculate_total).to eq(110) # (5*10) + (3*20)
    end

    it "returns 0 when there are no items" do
      invoice = create(:invoice)
      invoice.invoice_items.destroy_all
      expect(invoice.reload.calculate_total).to eq(0)
    end
  end

  describe "#calculate_total_ars" do
    context "when currency is USD" do
      it "converts total to ARS using exchange rate" do
        invoice = create(:invoice, currency: "USD", exchange_rate: 1200)
        invoice.invoice_items.destroy_all
        create(:invoice_item, invoice: invoice, quantity: 10, unit_cost: 50)

        # Total: 10 * 50 = 500 USD
        # In ARS: 500 * 1200 = 600000
        expect(invoice.reload.calculate_total_ars).to eq(600000)
      end
    end

    context "when currency is ARS" do
      it "returns total without conversion" do
        invoice = create(:invoice, :in_ars)
        invoice.invoice_items.destroy_all
        create(:invoice_item, invoice: invoice, quantity: 10, unit_cost: 5000)

        # Total: 10 * 5000 = 50000 ARS
        expect(invoice.reload.calculate_total_ars).to eq(50000)
      end
    end
  end

  # === TESTS FOR SIMPLE MODE ===

  describe "validations for simple mode" do
    subject { build(:invoice, :simple_mode) }

    it { is_expected.to validate_presence_of(:invoice_number) }
    it { is_expected.to validate_presence_of(:due_date) }
    it { is_expected.to validate_presence_of(:amount) }

    it "validates amount is greater than 0 when the invoice has no items" do
      invoice = build(:invoice, :simple_mode, amount: 0)
      expect(invoice).not_to be_valid
      expect(invoice.errors[:amount]).to be_present
    end

    # An invoice with lines takes its amount from them and may sum to zero
    # (a warranty replacement); the lines are built before the save, so the
    # guard must see them in memory.
    it "accepts an amount of 0 when lines are built in memory" do
      invoice = build(:invoice, :simple_mode, amount: 0, supplier: create(:supplier))
      invoice.invoice_items.build(product: create(:product), quantity: 1, unit_cost: 0)
      expect(invoice).to be_valid
    end

    it "still rejects a negative amount when lines exist" do
      invoice = build(:invoice, :simple_mode, amount: -1)
      invoice.invoice_items.build(product: create(:product), quantity: 1, unit_cost: 0)
      expect(invoice).not_to be_valid
      expect(invoice.errors[:amount]).to be_present
    end
  end

  describe "validations for full mode" do
    it "requires invoice_items on update" do
      invoice = create(:invoice, has_items: true, status: "confirmed")
      invoice.invoice_items.clear
      invoice.valid?(:update)
      expect(invoice.errors[:invoice_items]).to be_present
    end
  end

  describe "#simple_mode?" do
    it "returns true for invoices without items" do
      invoice = build(:invoice, :simple_mode)
      expect(invoice.simple_mode?).to be true
    end

    it "returns false for invoices with items" do
      invoice = build(:invoice, :full_mode)
      expect(invoice.simple_mode?).to be false
    end
  end

  describe "#full_mode?" do
    it "returns true for invoices with items" do
      invoice = build(:invoice, :full_mode)
      expect(invoice.full_mode?).to be true
    end

    it "returns false for invoices without items" do
      invoice = build(:invoice, :simple_mode)
      expect(invoice.full_mode?).to be false
    end
  end

  describe "#total_amount" do
    context "in simple mode" do
      it "returns the amount field" do
        invoice = build(:invoice, :simple_mode, amount: 5000)
        expect(invoice.total_amount).to eq(5000)
      end
    end

    context "in full mode" do
      it "calculates from invoice_items" do
        invoice = create(:invoice, :full_mode)
        invoice.invoice_items.destroy_all
        create(:invoice_item, invoice: invoice, quantity: 10, unit_cost: 50)

        expect(invoice.reload.total_amount).to eq(500)
      end
    end
  end

  describe "#total_amount_ars" do
    it "converts USD to ARS using exchange_rate" do
      invoice = build(:invoice, :simple_mode,
                      amount: 1000,
                      currency: "USD",
                      exchange_rate: 1200)

      expect(invoice.total_amount_ars).to eq(1_200_000)
    end

    it "returns amount directly for ARS" do
      invoice = build(:invoice, :simple_mode,
                      amount: 500_000,
                      currency: "ARS",
                      exchange_rate: nil)

      expect(invoice.total_amount_ars).to eq(500_000)
    end
  end

  describe "#overdue?" do
    it "returns true for pending invoices past due date" do
      invoice = create(:invoice, :simple_mode,
                       status: "pending",
                       due_date: 1.day.ago)

      expect(invoice.overdue?).to be true
    end

    it "returns false for pending invoices not yet due" do
      invoice = create(:invoice, :simple_mode,
                       status: "pending",
                       due_date: 1.day.from_now)

      expect(invoice.overdue?).to be false
    end

    it "returns false for paid invoices" do
      invoice = create(:invoice, :simple_mode,
                       status: "paid",
                       due_date: 1.day.ago)

      expect(invoice.overdue?).to be false
    end
  end

  describe "#days_until_due" do
    it "returns positive days for future due date" do
      invoice = build(:invoice, :simple_mode, due_date: 5.days.from_now.to_date)
      expect(invoice.days_until_due).to eq(5)
    end

    it "returns negative days for past due date" do
      invoice = build(:invoice, :simple_mode, due_date: 3.days.ago.to_date)
      expect(invoice.days_until_due).to eq(-3)
    end

    it "returns nil when due_date is not set" do
      invoice = build(:invoice, :full_mode)
      expect(invoice.days_until_due).to be_nil
    end
  end

  describe "#mark_as_paid!" do
    let(:invoice) { create(:invoice, :simple_mode, status: "pending") }

    it "updates status to paid" do
      invoice.mark_as_paid!
      expect(invoice.reload.paid_status?).to be true
    end

    it "records payment date" do
      payment_date = Date.yesterday
      invoice.mark_as_paid!(payment_date)

      expect(invoice.reload.paid_at.to_date).to eq(payment_date)
    end

    it "raises error if not simple mode" do
      full_invoice = create(:invoice, :full_mode)

      expect {
        full_invoice.mark_as_paid!
      }.to raise_error("Cannot mark as paid: not in simple mode")
    end

    it "raises error if already paid" do
      invoice.mark_as_paid!

      expect {
        invoice.mark_as_paid!
      }.to raise_error("Cannot mark as paid: already paid")
    end
  end

  describe "scopes" do
    let!(:simple_pending) { create(:invoice, :simple_mode, status: "pending", due_date: 5.days.from_now) }
    let!(:simple_overdue) { create(:invoice, :simple_mode, status: "pending", due_date: 1.day.ago) }
    let!(:simple_paid) { create(:invoice, :simple_mode, status: "paid") }
    let!(:full_invoice) { create(:invoice, :full_mode) }

    describe ".simple_mode" do
      it "returns only simple mode invoices" do
        expect(Invoice.simple_mode).to include(simple_pending, simple_overdue, simple_paid)
        expect(Invoice.simple_mode).not_to include(full_invoice)
      end
    end

    describe ".full_mode" do
      it "returns only full mode invoices" do
        expect(Invoice.full_mode).to include(full_invoice)
        expect(Invoice.full_mode).not_to include(simple_pending)
      end
    end

    describe ".pending_payment" do
      it "returns only pending invoices" do
        expect(Invoice.pending_payment).to include(simple_pending, simple_overdue)
        expect(Invoice.pending_payment).not_to include(simple_paid, full_invoice)
      end
    end

    describe ".overdue" do
      it "returns only overdue invoices" do
        expect(Invoice.overdue).to include(simple_overdue)
        expect(Invoice.overdue).not_to include(simple_pending, simple_paid)
      end
    end

    describe ".due_soon" do
      it "returns invoices due within 7 days" do
        expect(Invoice.due_soon).to include(simple_pending, simple_overdue)
      end
    end

    describe ".due_today" do
      let!(:due_today) { create(:invoice, :simple_mode, status: "pending", due_date: Date.current) }
      let!(:due_tomorrow) { create(:invoice, :simple_mode, status: "pending", due_date: Date.current + 1.day) }

      it "returns only invoices due today" do
        expect(Invoice.due_today).to include(due_today)
        expect(Invoice.due_today).not_to include(due_tomorrow)
      end
    end

    describe ".due_this_week" do
      let!(:due_monday) { create(:invoice, :simple_mode, status: "pending", due_date: Date.current.beginning_of_week(:monday)) }
      let!(:due_friday) { create(:invoice, :simple_mode, status: "pending", due_date: Date.current.end_of_week(:monday) - 2.days) }
      let!(:due_next_week) { create(:invoice, :simple_mode, status: "pending", due_date: Date.current.end_of_week(:monday) + 1.day) }

      it "returns invoices due this week (monday to sunday)" do
        expect(Invoice.due_this_week).to include(due_monday, due_friday)
        expect(Invoice.due_this_week).not_to include(due_next_week)
      end
    end

    describe ".for_supplier" do
      let(:supplier_a) { create(:supplier, name: "Supplier A") }
      let(:supplier_b) { create(:supplier, name: "Supplier B") }
      let!(:invoice_a1) { create(:invoice, :simple_mode, supplier: supplier_a) }
      let!(:invoice_a2) { create(:invoice, :simple_mode, supplier: supplier_a) }
      let!(:invoice_b1) { create(:invoice, :simple_mode, supplier: supplier_b) }

      it "filters invoices by supplier" do
        result = Invoice.for_supplier(supplier_a)

        expect(result).to include(invoice_a1, invoice_a2)
        expect(result).not_to include(invoice_b1)
      end

      it "returns all invoices when supplier is nil" do
        result = Invoice.for_supplier(nil)

        expect(result).to include(invoice_a1, invoice_a2, invoice_b1)
      end

      it "returns all invoices when supplier is not present" do
        # Simulate an empty supplier but not nil
        result = Invoice.all.for_supplier(nil)

        expect(result).to include(invoice_a1, invoice_a2, invoice_b1)
      end
    end

    describe ".search_invoice" do
      let(:supplier) { create(:supplier) }
      let!(:invoice1) { create(:invoice, :simple_mode, supplier: supplier, invoice_number: "FAC-001") }
      let!(:invoice2) { create(:invoice, :simple_mode, supplier: supplier, invoice_number: "FAC-002") }
      let!(:invoice3) { create(:invoice, :simple_mode, supplier: supplier, invoice_number: "INV-12345") }

      it "finds invoices by exact invoice number" do
        result = Invoice.search_invoice("FAC-001")

        expect(result).to include(invoice1)
        expect(result).not_to include(invoice2, invoice3)
      end

      it "performs partial search" do
        result = Invoice.search_invoice("FAC")

        expect(result).to include(invoice1, invoice2)
        expect(result).not_to include(invoice3)
      end

      it "performs case-insensitive search" do
        result = Invoice.search_invoice("fac-001")

        expect(result).to include(invoice1)
      end

      it "returns all invoices when query is nil" do
        result = Invoice.search_invoice(nil)

        expect(result).to include(invoice1, invoice2, invoice3)
      end

      it "returns all invoices when query is blank" do
        result = Invoice.search_invoice("")

        expect(result).to include(invoice1, invoice2, invoice3)
      end

      it "can be chained with other scopes" do
        supplier_b = create(:supplier)
        invoice_b = create(:invoice, :simple_mode, supplier: supplier_b, invoice_number: "FAC-999")

        result = Invoice.for_supplier(supplier).search_invoice("FAC")

        expect(result).to include(invoice1, invoice2)
        expect(result).not_to include(invoice3, invoice_b)
      end
    end

    describe ".priority_order" do
      let(:supplier) { create(:supplier) }

      it "orders pending invoices before paid invoices" do
        paid_invoice = create(:invoice, :simple_mode, supplier: supplier, status: "paid", due_date: 1.day.from_now)
        pending_invoice = create(:invoice, :simple_mode, supplier: supplier, status: "pending", due_date: 5.days.from_now)

        result = [ paid_invoice, pending_invoice ].map(&:id)
        ordered_result = Invoice.where(id: result).priority_order.pluck(:id)

        expect(ordered_result.first).to eq(pending_invoice.id)
        expect(ordered_result.last).to eq(paid_invoice.id)
      end

      it "orders pending invoices by due_date (soonest first)" do
        pending_far = create(:invoice, :simple_mode, supplier: supplier, status: "pending", due_date: 10.days.from_now)
        pending_soon = create(:invoice, :simple_mode, supplier: supplier, status: "pending", due_date: 2.days.from_now)
        pending_today = create(:invoice, :simple_mode, supplier: supplier, status: "pending", due_date: Date.current)

        ids = [ pending_far, pending_soon, pending_today ].map(&:id)
        result = Invoice.where(id: ids).priority_order.pluck(:id)

        expect(result[0]).to eq(pending_today.id)
        expect(result[1]).to eq(pending_soon.id)
        expect(result[2]).to eq(pending_far.id)
      end

      it "orders overdue pending invoices first" do
        overdue = create(:invoice, :simple_mode, supplier: supplier, status: "pending", due_date: 3.days.ago)
        pending_today = create(:invoice, :simple_mode, supplier: supplier, status: "pending", due_date: Date.current)
        pending_future = create(:invoice, :simple_mode, supplier: supplier, status: "pending", due_date: 5.days.from_now)
        paid = create(:invoice, :simple_mode, supplier: supplier, status: "paid", due_date: 2.days.ago)

        ids = [ overdue, pending_today, pending_future, paid ].map(&:id)
        result = Invoice.where(id: ids).priority_order.pluck(:id)

        expect(result[0]).to eq(overdue.id)
        expect(result[1]).to eq(pending_today.id)
        expect(result[2]).to eq(pending_future.id)
        expect(result[3]).to eq(paid.id)
      end

      it "orders non-pending invoices by due_date after pending" do
        pending = create(:invoice, :simple_mode, supplier: supplier, status: "pending", due_date: 5.days.from_now)
        paid = create(:invoice, :simple_mode, supplier: supplier, status: "paid", due_date: 3.days.from_now)
        cancelled = create(:invoice, :simple_mode, supplier: supplier, status: "cancelled", due_date: 1.day.from_now)

        ids = [ pending, paid, cancelled ].map(&:id)
        result = Invoice.where(id: ids).priority_order.pluck(:id)

        # pending first, then the rest ordered by due_date (cancelled has the closest date)
        expect(result[0]).to eq(pending.id)
        expect(result[1]).to eq(cancelled.id)
        expect(result[2]).to eq(paid.id)
      end

      it "can be chained with other scopes" do
        supplier_b = create(:supplier, name: "Supplier B")
        invoice_a_pending = create(:invoice, :simple_mode, supplier: supplier, status: "pending", due_date: 5.days.from_now)
        invoice_a_paid = create(:invoice, :simple_mode, supplier: supplier, status: "paid", due_date: 1.day.from_now)
        invoice_b_pending = create(:invoice, :simple_mode, supplier: supplier_b, status: "pending", due_date: 2.days.from_now)

        result = Invoice.simple_mode.for_supplier(supplier).priority_order

        expect(result).to include(invoice_a_pending, invoice_a_paid)
        expect(result).not_to include(invoice_b_pending)
        expect(result.first).to eq(invoice_a_pending)
      end

      it "breaks ties on the due date by id, newest first" do
        due = 10.days.from_now.to_date
        older = create(:invoice, :simple_mode, due_date: due)
        newer = create(:invoice, :simple_mode, due_date: due)

        result = Invoice.where(id: [ older.id, newer.id ]).priority_order

        expect(result).to eq([ newer, older ])
      end
    end
  end

  describe ".by_status_filter" do
    let!(:pending_invoice) { create(:invoice, :simple_mode) }
    let!(:paid_invoice) { create(:invoice, :paid) }

    it "keeps only invoices in the given status" do
      expect(Invoice.by_status_filter("paid")).to contain_exactly(paid_invoice)
    end

    it "ignores a status outside the enum" do
      expect(Invoice.by_status_filter("bogus")).to contain_exactly(pending_invoice, paid_invoice)
    end
  end

  describe ".by_payment_date" do
    it "puts the most recently paid invoice first, whatever its due date" do
      paid_today = create(:invoice, :paid, due_date: 6.months.ago.to_date, paid_at: Date.current)
      paid_last_week = create(:invoice, :paid, due_date: 1.month.from_now.to_date, paid_at: 1.week.ago.to_date)

      result = Invoice.where(id: [ paid_today.id, paid_last_week.id ]).by_payment_date

      expect(result).to eq([ paid_today, paid_last_week ])
    end

    it "pushes invoices without a payment date to the end" do
      dated = create(:invoice, :paid, paid_at: 1.month.ago.to_date)
      undated = create(:invoice, :paid, paid_at: nil)

      result = Invoice.where(id: [ dated.id, undated.id ]).by_payment_date

      expect(result).to eq([ dated, undated ])
    end

    it "breaks ties on the payment date by id, newest first" do
      same_day = 3.days.ago.to_date
      older = create(:invoice, :paid, paid_at: same_day)
      newer = create(:invoice, :paid, paid_at: same_day)

      result = Invoice.where(id: [ older.id, newer.id ]).by_payment_date

      expect(result).to eq([ newer, older ])
    end
  end

  describe ".total_pending_amount_ars" do
    let(:supplier_a) { create(:supplier, name: "Supplier A") }
    let(:supplier_b) { create(:supplier, name: "Supplier B") }

    before do
      # Invoices en ARS
      create(:invoice, :simple_mode, supplier: supplier_a, status: "pending", amount: 1000, currency: "ARS")
      create(:invoice, :simple_mode, supplier: supplier_a, status: "pending", amount: 2000, currency: "ARS")
      create(:invoice, :simple_mode, supplier: supplier_b, status: "pending", amount: 5000, currency: "ARS")

      # Paid invoice (must not count)
      create(:invoice, :simple_mode, supplier: supplier_a, status: "paid", amount: 999, currency: "ARS")

      # Invoice in USD
      create(:invoice, :simple_mode, supplier: supplier_a, status: "pending", amount: 100, currency: "USD", exchange_rate: 1200)

      # Invoice in full mode (must not count in simple_mode)
      create(:invoice, :full_mode, supplier: supplier_a, status: "confirmed", amount: 888)
    end

    context "sin filtro de proveedor" do
      it "calcula el total de todas las facturas pendientes en ARS" do
        # supplier_a: 1000 + 2000 + (100*1200) = 123000
        # supplier_b: 5000
        # Total: 128000
        total = Invoice.total_pending_amount_ars

        expect(total).to eq(128_000)
      end
    end

    context "con filtro de proveedor" do
      it "calcula el total solo para el proveedor especificado" do
        # supplier_a: 1000 + 2000 + (100*1200) = 123000
        total = Invoice.total_pending_amount_ars(supplier: supplier_a)

        expect(total).to eq(123_000)
      end

      it "no incluye facturas de otros proveedores" do
        total = Invoice.total_pending_amount_ars(supplier: supplier_b)

        expect(total).to eq(5_000)
      end
    end

    context "con proveedor sin facturas pendientes" do
      it "retorna 0" do
        supplier_c = create(:supplier, name: "Supplier C")
        total = Invoice.total_pending_amount_ars(supplier: supplier_c)

        expect(total).to eq(0)
      end
    end

    it "no incluye facturas pagadas" do
      # We already created a paid one in the before block, we verify it is not counted
      total = Invoice.total_pending_amount_ars(supplier: supplier_a)

      # Must not include the 999 of the paid invoice
      expect(total).to eq(123_000) # No 123_999
    end
  end

  # === EARLY PAYMENT TESTS ===

  describe "callbacks" do
    describe "#set_early_payment_terms" do
      it "sets early payment terms from supplier on create" do
        supplier = create(:supplier, early_payment_days: 15, early_payment_discount_percentage: 5)
        invoice = create(:invoice, :simple_mode,
                        supplier: supplier,
                        purchase_date: Date.new(2026, 1, 10))

        expect(invoice.early_payment_due_date).to eq(Date.new(2026, 1, 25)) # 10 + 15 days
        expect(invoice.early_payment_discount_percentage).to eq(5)
      end

      it "does not set early payment terms if supplier has no discount configured" do
        supplier = create(:supplier, early_payment_days: nil, early_payment_discount_percentage: nil)
        invoice = create(:invoice, :simple_mode, supplier: supplier)

        expect(invoice.early_payment_due_date).to be_nil
        expect(invoice.early_payment_discount_percentage).to be_nil
      end

      it "does not override manually set early payment values" do
        supplier = create(:supplier, early_payment_days: 15, early_payment_discount_percentage: 5)
        invoice = Invoice.new(
          supplier: supplier,
          invoice_number: "TEST-001",
          amount: 1000,
          currency: "ARS",
          purchase_date: Date.new(2026, 1, 10),
          due_date: Date.new(2026, 2, 10),
          has_items: false,
          early_payment_due_date: Date.new(2026, 1, 20),
          early_payment_discount_percentage: 3
        )
        invoice.save!

        expect(invoice.early_payment_due_date).to eq(Date.new(2026, 1, 20))
        expect(invoice.early_payment_discount_percentage).to eq(3)
      end

      context "when the supplier bills both Proveedor and Impuestos with a discount" do
        let(:mixed) do
          create(:supplier, expense_types: %w[supplier taxes], early_payment_days: 10, early_payment_discount_percentage: 5)
        end

        it "gives a tax invoice no discount, so it is due in full" do
          invoice = create(:invoice, :simple_mode, :in_ars, supplier: mixed, expense_type: "taxes",
                           amount: 100_000, purchase_date: Date.current)

          expect(invoice.early_payment_due_date).to be_nil
          expect(invoice.early_payment_discount_percentage).to be_nil
          expect(invoice.amount_due_ars(Date.current)).to eq(100_000)
        end

        it "still gives a supplier invoice the discount" do
          invoice = create(:invoice, :simple_mode, :in_ars, supplier: mixed, amount: 100_000, purchase_date: Date.current)

          expect(invoice.early_payment_discount_percentage).to eq(5)
          expect(invoice.amount_due_ars(Date.current)).to eq(95_000)
        end

        it "drops a typed discount from a social charges invoice" do
          invoice = build(:invoice, :simple_mode, :in_ars, supplier: create(:supplier, expense_types: %w[social_charges]),
                          expense_type: "social_charges", early_payment_due_date: Date.current + 5,
                          early_payment_discount_percentage: 5)
          invoice.save!

          expect(invoice.early_payment_discount_percentage).to be_nil
          expect(invoice.early_payment_due_date).to be_nil
        end

        it "clears the discount when a supplier invoice is edited into a tax invoice" do
          invoice = create(:invoice, :simple_mode, :in_ars, supplier: mixed, amount: 100_000, purchase_date: Date.current)

          invoice.update!(expense_type: "taxes", period: Date.current.beginning_of_month)

          expect(invoice.reload).to have_attributes(early_payment_due_date: nil, early_payment_discount_percentage: nil)
        end
      end
    end
  end

  describe "scopes" do
    describe ".with_early_payment" do
      it "returns invoices with early_payment_due_date set" do
        invoice_with = create(:invoice, :simple_mode, early_payment_due_date: 15.days.from_now)
        invoice_without = create(:invoice, :simple_mode, early_payment_due_date: nil)

        expect(Invoice.with_early_payment).to include(invoice_with)
        expect(Invoice.with_early_payment).not_to include(invoice_without)
      end
    end

    describe ".discount_available" do
      it "returns invoices with discount not yet expired" do
        invoice_available = create(:invoice, :simple_mode, early_payment_due_date: 5.days.from_now)
        invoice_expired = create(:invoice, :simple_mode, early_payment_due_date: 1.day.ago)

        expect(Invoice.discount_available).to include(invoice_available)
        expect(Invoice.discount_available).not_to include(invoice_expired)
      end
    end
  end

  describe "#amount_with_discount" do
    it "returns discounted amount when discount percentage is set" do
      invoice = build(:invoice, :simple_mode,
                     amount: 1000,
                     early_payment_discount_percentage: 5)

      expect(invoice.amount_with_discount).to eq(950) # 1000 - 5% = 950
    end

    it "returns full amount when no discount percentage" do
      invoice = build(:invoice, :simple_mode, amount: 1000, early_payment_discount_percentage: nil)

      expect(invoice.amount_with_discount).to eq(1000)
    end
  end

  describe "#amount_with_discount_ars" do
    it "converts USD discounted amount to ARS" do
      invoice = build(:invoice, :simple_mode,
                     amount: 1000,
                     currency: "USD",
                     exchange_rate: 1200,
                     early_payment_discount_percentage: 5)

      # 1000 - 5% = 950
      # 950 * 1200 = 1,140,000
      expect(invoice.amount_with_discount_ars).to eq(1_140_000)
    end

    it "returns ARS amount directly" do
      invoice = build(:invoice, :simple_mode,
                     amount: 100_000,
                     currency: "ARS",
                     early_payment_discount_percentage: 10)

      # 100,000 - 10% = 90,000
      expect(invoice.amount_with_discount_ars).to eq(90_000)
    end
  end

  describe "#eligible_for_discount?" do
    it "returns true when payment date is before or equal to early_payment_due_date" do
      invoice = build(:invoice, :simple_mode,
                     early_payment_due_date: Date.new(2026, 1, 20))

      expect(invoice.eligible_for_discount?(Date.new(2026, 1, 20))).to be true
      expect(invoice.eligible_for_discount?(Date.new(2026, 1, 15))).to be true
    end

    it "returns false when payment date is after early_payment_due_date" do
      invoice = build(:invoice, :simple_mode,
                     early_payment_due_date: Date.new(2026, 1, 20))

      expect(invoice.eligible_for_discount?(Date.new(2026, 1, 21))).to be false
    end

    it "returns false when no early_payment_due_date set" do
      invoice = build(:invoice, :simple_mode, early_payment_due_date: nil)

      expect(invoice.eligible_for_discount?).to be false
    end
  end

  describe "#potential_savings" do
    it "calculates savings when discount is available" do
      invoice = build(:invoice, :simple_mode,
                     amount: 1000,
                     early_payment_due_date: 5.days.from_now,
                     early_payment_discount_percentage: 5)

      expect(invoice.potential_savings).to eq(50) # 1000 * 5% = 50
    end

    it "returns 0 when no discount configured" do
      invoice = build(:invoice, :simple_mode,
                     amount: 1000,
                     early_payment_due_date: nil)

      expect(invoice.potential_savings).to eq(0)
    end
  end

  describe "#potential_savings_ars" do
    it "converts USD savings to ARS" do
      invoice = build(:invoice, :simple_mode,
                     amount: 1000,
                     currency: "USD",
                     exchange_rate: 1200,
                     early_payment_due_date: 5.days.from_now,
                     early_payment_discount_percentage: 5)

      # Savings: 1000 * 5% = 50
      # In ARS: 50 * 1200 = 60,000
      expect(invoice.potential_savings_ars).to eq(60_000)
    end
  end

  describe "#days_until_discount_expires" do
    it "returns positive days when discount is in the future" do
      invoice = build(:invoice, :simple_mode,
                     early_payment_due_date: 5.days.from_now.to_date)

      expect(invoice.days_until_discount_expires).to eq(5)
    end

    it "returns negative days when discount expired" do
      invoice = build(:invoice, :simple_mode,
                     early_payment_due_date: 3.days.ago.to_date)

      expect(invoice.days_until_discount_expires).to eq(-3)
    end

    it "returns nil when no early_payment_due_date" do
      invoice = build(:invoice, :simple_mode, early_payment_due_date: nil)

      expect(invoice.days_until_discount_expires).to be_nil
    end
  end

  describe ".due_or_discount_in_period" do
    let(:supplier) { create(:supplier) }
    let(:start_date) { Date.current.beginning_of_week(:monday) }
    let(:end_date)   { Date.current.end_of_week(:monday) }

    it "includes invoices with due_date in the period" do
      invoice = create(:invoice, :simple_mode,
                       supplier: supplier,
                       status: "pending",
                       due_date: Date.current)

      expect(Invoice.due_or_discount_in_period(start_date, end_date)).to include(invoice)
    end

    it "excludes invoices with due_date outside the period" do
      invoice = create(:invoice, :simple_mode,
                       supplier: supplier,
                       status: "pending",
                       due_date: end_date + 1.day)

      expect(Invoice.due_or_discount_in_period(start_date, end_date)).not_to include(invoice)
    end

    it "includes invoices with early_payment_due_date in the period and still valid" do
      # We use Date.current to guarantee it falls within start_date..end_date
      # regardless of the day the test runs (avoids failures on Sunday).
      invoice = create(:invoice, :simple_mode,
                       supplier: supplier,
                       status: "pending",
                       due_date: end_date + 30.days,
                       early_payment_due_date: Date.current,
                       early_payment_discount_percentage: 5)

      expect(Invoice.due_or_discount_in_period(start_date, end_date)).to include(invoice)
    end

    it "excludes invoices with early_payment_due_date in the period but already expired" do
      invoice = create(:invoice, :simple_mode,
                       supplier: supplier,
                       status: "pending",
                       due_date: end_date + 30.days,
                       early_payment_due_date: Date.current - 1.day,
                       early_payment_discount_percentage: 5)

      expect(Invoice.due_or_discount_in_period(start_date, end_date)).not_to include(invoice)
    end

    it "excludes paid invoices" do
      invoice = create(:invoice, :simple_mode,
                       supplier: supplier,
                       status: "paid",
                       due_date: Date.current)

      expect(Invoice.due_or_discount_in_period(start_date, end_date)).not_to include(invoice)
    end

    it "excludes full_mode invoices" do
      invoice = create(:invoice, :full_mode,
                       supplier: supplier,
                       status: "pending",
                       early_payment_due_date: Date.current + 1.day)

      expect(Invoice.due_or_discount_in_period(start_date, end_date)).not_to include(invoice)
    end

    it "does not duplicate invoices with both dates in the period" do
      invoice = create(:invoice, :simple_mode,
                       supplier: supplier,
                       status: "pending",
                       due_date: Date.current,
                       early_payment_due_date: Date.current + 1.day,
                       early_payment_discount_percentage: 5)

      result = Invoice.due_or_discount_in_period(start_date, end_date)
      expect(result.where(id: invoice.id).count).to eq(1)
    end
  end

  describe "expense type" do
    it "defaults to supplier" do
      invoice = create(:invoice, :simple_mode, :in_ars)
      expect(invoice.expense_type).to eq("supplier")
    end

    it "rejects product lines on a non-supplier invoice" do
      invoice = build(:invoice, :full_mode, expense_type: "taxes")
      expect(invoice).not_to be_valid
      expect(invoice.errors[:base]).to include("Solo las facturas de proveedor llevan productos")
    end

    it "maps each type to its cash category" do
      expect(build(:invoice, expense_type: "supplier").cash_category_attrs).to eq(category: "suppliers", subcategory: nil)
      expect(build(:invoice, expense_type: "taxes").cash_category_attrs).to eq(category: "fixed_expense", subcategory: "taxes")
      expect(build(:invoice, expense_type: "utilities").cash_category_attrs).to eq(category: "fixed_expense", subcategory: "utilities")
      expect(build(:invoice, expense_type: "social_charges").cash_category_attrs).to eq(category: "fixed_expense", subcategory: "social_charges")
    end

    it "filters by type and ignores an unknown one" do
      taxes = create(:invoice, :simple_mode, :in_ars, supplier: create(:supplier, expense_types: %w[taxes]), expense_type: "taxes")
      supplier = create(:invoice, :simple_mode, :in_ars)
      expect(Invoice.by_expense_type("taxes")).to contain_exactly(taxes)
      expect(Invoice.by_expense_type("bogus")).to include(taxes, supplier)
      expect(Invoice.by_expense_type("")).to include(taxes, supplier)
    end
  end

  describe "supplier billing the type" do
    let(:merchandise) { create(:supplier) }
    let(:afip) { create(:supplier, name: "AFIP", expense_types: %w[taxes]) }

    it "refuses a type the supplier does not bill" do
      invoice = build(:invoice, :simple_mode, :in_ars, supplier: merchandise, expense_type: "taxes")
      expect(invoice).not_to be_valid
      expect(invoice.errors[:base]).to include("#{merchandise.name} no factura Impuestos")
    end

    it "accepts a type the supplier bills" do
      expect(build(:invoice, :simple_mode, :in_ars, supplier: afip, expense_type: "taxes")).to be_valid
    end

    it "keeps updating an invoice whose supplier later dropped its type" do
      invoice = create(:invoice, :simple_mode, :in_ars, supplier: afip, expense_type: "taxes")
      afip.update!(expense_types: %w[utilities])

      expect { invoice.reload.update!(status: "paid", paid_at: Date.current) }.not_to raise_error
    end

    it "refuses changing the type to one the supplier does not bill" do
      invoice = create(:invoice, :simple_mode, :in_ars, supplier: afip, expense_type: "taxes")
      invoice.expense_type = "utilities"

      expect(invoice).not_to be_valid
      expect(invoice.errors[:base]).to include("AFIP no factura Servicios")
    end

    it "refuses changing the supplier to one that does not bill the type" do
      invoice = create(:invoice, :simple_mode, :in_ars, supplier: afip, expense_type: "taxes")
      invoice.supplier = merchandise

      expect(invoice).not_to be_valid
    end
  end

  describe "identification by type" do
    let(:afip) { create(:supplier, name: "AFIP", expense_types: %w[taxes utilities social_charges]) }

    def taxes_invoice(**attrs)
      build(:invoice, :simple_mode, :in_ars, supplier: afip, expense_type: "taxes", **attrs)
    end

    it "requires an invoice number on a supplier invoice" do
      invoice = build(:invoice, :simple_mode, :in_ars, invoice_number: nil)
      expect(invoice).not_to be_valid
      expect(invoice.errors[:invoice_number]).to be_present
    end

    it "clears the period and detail of a supplier invoice" do
      invoice = build(:invoice, :simple_mode, :in_ars, supplier: create(:supplier), period: Date.new(2026, 9, 1), detail: "IVA")
      invoice.save!
      expect(invoice.reload.period).to be_nil
      expect(invoice.detail).to be_nil
    end

    it "requires a period on a non-supplier invoice" do
      invoice = taxes_invoice(period: nil)
      expect(invoice).not_to be_valid
      expect(invoice.errors[:base]).to include("Falta el período")
    end

    it "accepts a non-supplier invoice without a number" do
      expect(taxes_invoice(invoice_number: nil)).to be_valid
    end

    it "never keeps the number of a non-supplier invoice" do
      invoice = taxes_invoice(invoice_number: "IIBB 09/2026")
      invoice.save!
      expect(invoice.reload.invoice_number).to be_nil
    end

    it "requires pesos on a non-supplier invoice" do
      invoice = build(:invoice, :simple_mode, supplier: afip, expense_type: "utilities", currency: "USD", exchange_rate: 1200)
      expect(invoice).not_to be_valid
      expect(invoice.errors[:base]).to eq([ "Las boletas de Servicios son en pesos" ])
    end

    it "caps the detail at 40 characters" do
      expect(taxes_invoice(detail: "a" * 40)).to be_valid

      invoice = taxes_invoice(detail: "a" * 41)
      expect(invoice).not_to be_valid
      expect(invoice.errors[:base]).to include("El detalle no puede superar 40 caracteres")
    end

    it "stores a blank detail as nil" do
      invoice = taxes_invoice(detail: "   ")
      invoice.valid?
      expect(invoice.detail).to be_nil
    end

    it "keeps what the other type does not use until the save goes through" do
      both = create(:supplier, expense_types: %w[supplier taxes])
      invoice = create(:invoice, :simple_mode, :in_ars, supplier: both, invoice_number: "FAC-1")
      invoice.assign_attributes(expense_type: "taxes", period: nil)

      expect(invoice).not_to be_valid
      expect(invoice.invoice_number).to eq("FAC-1")
    end

    it "stores the period as the first of the month" do
      invoice = taxes_invoice(period: Date.new(2026, 9, 17))
      invoice.valid?
      expect(invoice.period).to eq(Date.new(2026, 9, 1))
    end

    it "clears the exchange rate of a non-supplier invoice" do
      invoice = taxes_invoice(exchange_rate: 1200)
      invoice.save!
      expect(invoice.reload.exchange_rate).to be_nil
    end

    describe "#reference" do
      it "is the invoice number of a supplier invoice" do
        expect(build(:invoice, :simple_mode, invoice_number: "FAC-001").reference).to eq("FAC-001")
      end

      it "joins the detail and the period on a non-supplier invoice" do
        invoice = taxes_invoice(detail: "IVA", period: Date.new(2026, 9, 1))
        expect(invoice.reference).to eq("IVA · 09/2026")
      end

      it "is only the period without a detail" do
        invoice = taxes_invoice(detail: nil, period: Date.new(2026, 9, 1))
        expect(invoice.reference).to eq("09/2026")
      end

      it "keeps the stored reference apart from an unsaved edit" do
        invoice = taxes_invoice(detail: "IVA", period: Date.new(2026, 9, 1))
        invoice.save!
        invoice.assign_attributes(detail: "Ganancias", expense_type: "supplier", invoice_number: "")

        expect(invoice.reference_was).to eq("IVA · 09/2026")
      end

      it "is blank while the period is missing" do
        expect(taxes_invoice(period: nil).reference).to eq("")
      end
    end
  end

  describe ".search_invoice by detail and period" do
    let(:afip) { create(:supplier, name: "AFIP", expense_types: %w[taxes]) }
    let!(:iva) { create(:invoice, :simple_mode, :in_ars, supplier: afip, expense_type: "taxes", detail: "IVA", period: Date.new(2026, 9, 1)) }
    let!(:gan) { create(:invoice, :simple_mode, :in_ars, supplier: afip, expense_type: "taxes", detail: "Ganancias", period: Date.new(2026, 8, 1)) }
    let!(:fac) { create(:invoice, :simple_mode, :in_ars, invoice_number: "FAC-001") }

    it "matches the detail, ignoring case" do
      expect(Invoice.search_invoice("iva")).to contain_exactly(iva)
    end

    it "matches the period as month and year" do
      expect(Invoice.search_invoice("09/2026")).to contain_exactly(iva)
      expect(Invoice.search_invoice("08/2026")).to contain_exactly(gan)
    end

    it "matches the reference as it is displayed" do
      expect(Invoice.search_invoice("IVA · 09/2026")).to contain_exactly(iva)
      expect(Invoice.search_invoice("Ganancias · 08")).to contain_exactly(gan)
    end

    it "still matches a supplier invoice number" do
      expect(Invoice.search_invoice("FAC-001")).to contain_exactly(fac)
    end

    it "treats wildcard characters as plain text" do
      expect(Invoice.search_invoice("%")).to be_empty
      expect(Invoice.search_invoice("_")).to be_empty
    end
  end

  describe "#amount_due_ars" do
    it "is the peso amount without a discount" do
      invoice = build(:invoice, :simple_mode, :in_ars, amount: 100_000)
      expect(invoice.amount_due_ars(Date.current)).to eq(100_000)
    end

    it "converts a USD invoice at its exchange rate" do
      invoice = build(:invoice, :simple_mode, currency: "USD", exchange_rate: 1200, amount: 1000)
      expect(invoice.amount_due_ars(Date.current)).to eq(1_200_000)
    end

    it "applies the early-payment discount only up to its deadline" do
      invoice = build(:invoice, :simple_mode, :in_ars, amount: 100_000,
                      early_payment_due_date: Date.current + 5, early_payment_discount_percentage: 5)
      expect(invoice.amount_due_ars(Date.current)).to eq(95_000)
      expect(invoice.amount_due_ars(Date.current + 6)).to eq(100_000)
    end

    it "applies the discount to a USD invoice in pesos" do
      invoice = build(:invoice, :simple_mode, currency: "USD", exchange_rate: 1200, amount: 1000,
                      early_payment_due_date: Date.current + 5, early_payment_discount_percentage: 10)
      expect(invoice.amount_due_ars(Date.current)).to eq(1_080_000)
    end
  end
end
