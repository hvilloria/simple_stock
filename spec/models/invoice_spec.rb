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
      # Limpiar items por defecto
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

  # === TESTS PARA MODO SIMPLE ===

  describe "validations for simple mode" do
    subject { build(:invoice, :simple_mode) }

    it { is_expected.to validate_presence_of(:invoice_number) }
    it { is_expected.to validate_presence_of(:due_date) }
    it { is_expected.to validate_presence_of(:amount) }

    it "validates amount is greater than 0" do
      invoice = build(:invoice, :simple_mode, amount: 0)
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
        # Simular supplier vacío pero no nil
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

        # pending primero, luego los demás ordenados por due_date (cancelled tiene fecha más cercana)
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

      # Invoice pagada (no debe contar)
      create(:invoice, :simple_mode, supplier: supplier_a, status: "paid", amount: 999, currency: "ARS")

      # Invoice en USD
      create(:invoice, :simple_mode, supplier: supplier_a, status: "pending", amount: 100, currency: "USD", exchange_rate: 1200)

      # Invoice en modo completo (no debe contar en simple_mode)
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
      # Ya creamos una pagada en el before, verificamos que no se cuenta
      total = Invoice.total_pending_amount_ars(supplier: supplier_a)

      # No debe incluir los 999 de la factura pagada
      expect(total).to eq(123_000) # No 123_999
    end
  end
end
