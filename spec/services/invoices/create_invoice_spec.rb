require "rails_helper"

RSpec::Matchers.define_negated_matcher :not_change, :change

RSpec.describe Invoices::CreateInvoice do
  let!(:supplier) { create(:supplier) }

  describe ".call" do
    context "with valid parameters" do
      it "creates a invoice in simple mode" do
        result = described_class.call(
          supplier: supplier,
          invoice_number: "FAC-001",
          amount: 5000,
          currency: "USD",
          exchange_rate: 1200,
          purchase_date: Date.current,
          due_date: 30.days.from_now,
          notes: "Test invoice"
        )

        expect(result.success?).to be true
        expect(result.record).to be_a(Invoice)
        expect(result.record.simple_mode?).to be true
        expect(result.record.pending_status?).to be true
      end

      it "sets correct attributes" do
        result = described_class.call(
          supplier: supplier,
          invoice_number: "FAC-001",
          amount: 5000,
          currency: "USD",
          exchange_rate: 1200,
          purchase_date: Date.current,
          due_date: 30.days.from_now
        )

        invoice = result.record
        expect(invoice.supplier).to eq(supplier)
        expect(invoice.invoice_number).to eq("FAC-001")
        expect(invoice.amount).to eq(5000)
        expect(invoice.currency).to eq("USD")
        expect(invoice.exchange_rate).to eq(1200)
        expect(invoice.has_items).to be false
      end

      it "does not create invoice_items" do
        expect {
          described_class.call(
            supplier: supplier,
            invoice_number: "FAC-001",
            amount: 5000,
            currency: "USD",
            exchange_rate: 1200,
            purchase_date: Date.current,
            due_date: 30.days.from_now
          )
        }.not_to change(InvoiceItem, :count)
      end

      it "does not create stock_movements" do
        expect {
          described_class.call(
            supplier: supplier,
            invoice_number: "FAC-001",
            amount: 5000,
            currency: "USD",
            exchange_rate: 1200,
            purchase_date: Date.current,
            due_date: 30.days.from_now
          )
        }.not_to change(StockMovement, :count)
      end

      it "accepts ARS currency without exchange_rate" do
        result = described_class.call(
          supplier: supplier,
          invoice_number: "FAC-002",
          amount: 500_000,
          currency: "ARS",
          purchase_date: Date.current,
          due_date: 30.days.from_now
        )

        expect(result.success?).to be true
        expect(result.record.currency).to eq("ARS")
        expect(result.record.exchange_rate).to be_nil
      end
    end

    context "with invalid parameters" do
      it "fails without supplier" do
        result = described_class.call(
          supplier: nil,
          invoice_number: "FAC-001",
          amount: 5000,
          currency: "USD",
          exchange_rate: 1200,
          purchase_date: Date.current,
          due_date: 30.days.from_now
        )

        expect(result.success?).to be false
        expect(result.errors).to include("Supplier is required")
      end

      it "fails without invoice number" do
        result = described_class.call(
          supplier: supplier,
          invoice_number: "",
          amount: 5000,
          currency: "USD",
          exchange_rate: 1200,
          purchase_date: Date.current,
          due_date: 30.days.from_now
        )

        expect(result.success?).to be false
        expect(result.errors).to include("Invoice number is required")
      end

      it "fails with amount zero" do
        result = described_class.call(
          supplier: supplier,
          invoice_number: "FAC-001",
          amount: 0,
          currency: "USD",
          exchange_rate: 1200,
          purchase_date: Date.current,
          due_date: 30.days.from_now
        )

        expect(result.success?).to be false
        expect(result.errors).to include("Amount must be greater than zero")
      end

      it "fails with negative amount" do
        result = described_class.call(
          supplier: supplier,
          invoice_number: "FAC-001",
          amount: -100,
          currency: "USD",
          exchange_rate: 1200,
          purchase_date: Date.current,
          due_date: 30.days.from_now
        )

        expect(result.success?).to be false
        expect(result.errors).to include("Amount must be greater than zero")
      end

      it "fails without exchange_rate for USD" do
        result = described_class.call(
          supplier: supplier,
          invoice_number: "FAC-001",
          amount: 5000,
          currency: "USD",
          exchange_rate: nil,
          purchase_date: Date.current,
          due_date: 30.days.from_now
        )

        expect(result.success?).to be false
        expect(result.errors).to include("Exchange rate required for USD invoices")
      end

      it "fails with zero exchange_rate for USD" do
        result = described_class.call(
          supplier: supplier,
          invoice_number: "FAC-001",
          amount: 5000,
          currency: "USD",
          exchange_rate: 0,
          purchase_date: Date.current,
          due_date: 30.days.from_now
        )

        expect(result.success?).to be false
        expect(result.errors).to include("Exchange rate required for USD invoices")
      end

      it "fails with invalid currency" do
        result = described_class.call(
          supplier: supplier,
          invoice_number: "FAC-001",
          amount: 5000,
          currency: "EUR",
          exchange_rate: 1200,
          purchase_date: Date.current,
          due_date: 30.days.from_now
        )

        expect(result.success?).to be false
        expect(result.errors).to include("Invalid currency. Must be USD or ARS")
      end

      it "fails when due_date is before purchase_date" do
        result = described_class.call(
          supplier: supplier,
          invoice_number: "FAC-001",
          amount: 5000,
          currency: "USD",
          exchange_rate: 1200,
          purchase_date: Date.current,
          due_date: 1.day.ago.to_date
        )

        expect(result.success?).to be false
        expect(result.errors).to include("Due date cannot be before purchase date")
      end

      it "fails without due_date" do
        result = described_class.call(
          supplier: supplier,
          invoice_number: "FAC-001",
          amount: 5000,
          currency: "USD",
          exchange_rate: 1200,
          purchase_date: Date.current,
          due_date: nil
        )

        expect(result.success?).to be false
        expect(result.errors).to include("Due date is required")
      end
    end

    context "with default values" do
      it "defaults purchase_date to today" do
        result = described_class.call(
          supplier: supplier,
          invoice_number: "FAC-001",
          amount: 5000,
          currency: "USD",
          exchange_rate: 1200,
          due_date: 30.days.from_now
        )

        expect(result.success?).to be true
        expect(result.record.purchase_date).to eq(Date.current)
      end
    end

    context "with early payment discount" do
      it "creates invoice with early payment terms" do
        result = described_class.call(
          supplier: supplier,
          invoice_number: "FAC-001",
          amount: 5000,
          currency: "USD",
          exchange_rate: 1200,
          purchase_date: Date.current,
          due_date: 30.days.from_now,
          early_payment_due_date: 15.days.from_now.to_date,
          early_payment_discount_percentage: 5
        )

        expect(result.success?).to be true
        expect(result.record.early_payment_due_date).to eq(15.days.from_now.to_date)
        expect(result.record.early_payment_discount_percentage).to eq(5)
      end

      it "creates invoice without early payment terms when not provided" do
        result = described_class.call(
          supplier: supplier,
          invoice_number: "FAC-001",
          amount: 5000,
          currency: "USD",
          exchange_rate: 1200,
          purchase_date: Date.current,
          due_date: 30.days.from_now
        )

        expect(result.success?).to be true
        expect(result.record.early_payment_due_date).to be_nil
        expect(result.record.early_payment_discount_percentage).to be_nil
      end

      it "auto-sets early payment terms from supplier if supplier has discount configured" do
        supplier_with_discount = create(:supplier,
                                        early_payment_days: 15,
                                        early_payment_discount_percentage: 5)

        result = described_class.call(
          supplier: supplier_with_discount,
          invoice_number: "FAC-001",
          amount: 5000,
          currency: "USD",
          exchange_rate: 1200,
          purchase_date: Date.new(2026, 1, 10),
          due_date: Date.new(2026, 2, 10)
        )

        expect(result.success?).to be true
        # Auto-calculated: 2026-01-10 + 15 days = 2026-01-25
        expect(result.record.early_payment_due_date).to eq(Date.new(2026, 1, 25))
        expect(result.record.early_payment_discount_percentage).to eq(5)
      end

      it "allows manual override of supplier discount terms" do
        supplier_with_discount = create(:supplier,
                                        early_payment_days: 15,
                                        early_payment_discount_percentage: 5)

        result = described_class.call(
          supplier: supplier_with_discount,
          invoice_number: "FAC-001",
          amount: 5000,
          currency: "USD",
          exchange_rate: 1200,
          purchase_date: Date.new(2026, 1, 10),
          due_date: Date.new(2026, 2, 10),
          early_payment_due_date: Date.new(2026, 1, 20),
          early_payment_discount_percentage: 3
        )

        expect(result.success?).to be true
        expect(result.record.early_payment_due_date).to eq(Date.new(2026, 1, 20))
        expect(result.record.early_payment_discount_percentage).to eq(3)
      end
    end

    context "error shape" do
      # The Result contract is a flat array of strings. Array#join flattens a
      # nested array, so the controller's output would not reveal the nesting.
      it "returns a flat array of messages on a model validation failure" do
        invalid = Invoice.new
        invalid.errors.add(:base, "Boom")
        allow_any_instance_of(Invoice).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(invalid))

        result = described_class.call(
          supplier: supplier,
          invoice_number: "FAC-002",
          amount: 5000,
          currency: "USD",
          exchange_rate: 1200,
          purchase_date: Date.current,
          due_date: 30.days.from_now
        )

        expect(result.success?).to be false
        expect(result.errors).to eq([ "Boom" ])
      end
    end

    context "with product lines" do
      let!(:location) { create(:stock_location) }
      let(:filter)  { create(:product, name: "Filtro de aceite", current_stock: 0) }
      # Seeded through a movement: current_stock is recalculated as the sum of
      # the movements, so a factory column alone would vanish on the first one.
      let(:pads) do
        create(:product, name: "Pastillas", current_stock: 0).tap do |product|
          Inventory::AdjustStock.call(product: product, stock_location: location,
                                      movement_type: "purchase", quantity: 2)
        end
      end

      def call_with(items, amount: nil, **overrides)
        described_class.call(
          **{ supplier: supplier, invoice_number: "FAC-100", amount: amount, currency: "ARS",
              purchase_date: Date.current, due_date: 30.days.from_now, items: items }.merge(overrides)
        )
      end

      it "stores the sum of the lines as the amount and ignores the submitted one" do
        result = call_with(
          [ { product_id: filter.id, quantity: 10, unit_cost: 4500 },
            { product_id: pads.id, quantity: 4, unit_cost: 21_000 } ],
          amount: 1
        )

        expect(result.success?).to be true
        invoice = result.record
        expect(invoice.amount).to eq(129_000)
        expect(invoice.has_items).to be false
        expect(invoice.invoice_items.count).to eq(2)
        expect(Invoice.simple_mode.pending_payment).to include(invoice)
      end

      it "adds each line's quantity to stock through purchase movements referencing the invoice" do
        result = call_with([ { product_id: filter.id, quantity: 10, unit_cost: 4500 },
                             { product_id: pads.id, quantity: 4, unit_cost: 21_000 } ])

        invoice = result.record
        expect(filter.reload.current_stock).to eq(10)
        expect(pads.reload.current_stock).to eq(6)
        movements = invoice.stock_movements.order(:id)
        expect(movements.map(&:movement_type)).to eq(%w[purchase purchase])
        expect(movements.map(&:quantity)).to eq([ 10, 4 ])
        expect(movements.map(&:stock_location)).to all(eq(location))
      end

      it "writes one movement per line, so the same product on two lines moves twice" do
        result = call_with([ { product_id: filter.id, quantity: 3, unit_cost: 4500 },
                             { product_id: filter.id, quantity: 2, unit_cost: 4000 } ])

        expect(result.record.invoice_items.count).to eq(2)
        expect(result.record.amount).to eq(21_500)
        expect(filter.reload.current_stock).to eq(5)
      end

      it "ignores rows without a product or without a positive quantity" do
        result = call_with([ { product_id: filter.id, quantity: 10, unit_cost: 4500 },
                             { product_id: "", quantity: 5, unit_cost: 100 },
                             { product_id: pads.id, quantity: 0, unit_cost: 21_000 },
                             { product_id: pads.id, quantity: "", unit_cost: 21_000 } ])

        expect(result.success?).to be true
        expect(result.record.invoice_items.count).to eq(1)
        expect(result.record.amount).to eq(45_000)
        expect(pads.reload.current_stock).to eq(2)
      end

      it "reads a blank unit cost as zero and still moves the stock" do
        result = call_with([ { product_id: filter.id, quantity: 2, unit_cost: "" } ])

        expect(result.success?).to be true
        expect(result.record.amount).to eq(0)
        expect(result.record.invoice_items.first.unit_cost).to eq(0)
        expect(filter.reload.current_stock).to eq(2)
      end

      it "accepts string keys, the shape params arrive in" do
        result = call_with([ { "product_id" => filter.id.to_s, "quantity" => "2", "unit_cost" => "4500" } ])

        expect(result.success?).to be true
        expect(result.record.amount).to eq(9_000)
      end

      it "rejects a negative unit cost" do
        result = call_with([ { product_id: filter.id, quantity: 1, unit_cost: -1 } ])

        expect(result.success?).to be false
        expect(result.errors).to include("Unit cost cannot be negative")
        expect(filter.reload.current_stock).to eq(0)
      end

      it "rejects an unparseable unit cost instead of reading it as free" do
        result = call_with([ { product_id: filter.id, quantity: 1, unit_cost: nil } ])

        expect(result.success?).to be false
        expect(result.errors).to include("Unit cost is not a number")
        expect(Invoice.count).to eq(0)
      end

      it "rejects a product that does not exist" do
        result = call_with([ { product_id: 999_999, quantity: 1, unit_cost: 100 } ])

        expect(result.success?).to be false
        expect(result.errors).to include("Product not found: 999999")
      end

      it "does not require a typed amount when there are complete lines" do
        result = call_with([ { product_id: filter.id, quantity: 1, unit_cost: 100 } ], amount: nil)

        expect(result.success?).to be true
      end

      it "still requires a positive amount when every row is incomplete" do
        result = call_with([ { product_id: filter.id, quantity: 0, unit_cost: 100 } ], amount: nil)

        expect(result.success?).to be false
        expect(result.errors).to include("Amount must be greater than zero")
      end

      it "refuses a bad header without writing anything" do
        expect {
          result = call_with([ { product_id: filter.id, quantity: 10, unit_cost: 4500 } ],
                             due_date: Date.current - 1)
          expect(result.success?).to be false
        }.to not_change(Invoice, :count)
          .and not_change(InvoiceItem, :count)
          .and not_change(StockMovement, :count)
        expect(filter.reload.current_stock).to eq(0)
      end

      it "rolls everything back when a stock movement fails" do
        allow(Inventory::AdjustStock).to receive(:call)
          .and_return(Result.new(success?: false, record: nil, errors: [ "Error adjusting stock" ]))

        expect {
          result = call_with([ { product_id: filter.id, quantity: 10, unit_cost: 4500 } ])
          expect(result.success?).to be false
          expect(result.errors).to include("Error adjusting stock")
        }.to not_change(Invoice, :count).and not_change(InvoiceItem, :count)
      end

      it "sets the supplier's early-payment terms and applies the discount to the sum" do
        discounting = create(:supplier, :with_early_payment_discount)
        result = call_with([ { product_id: filter.id, quantity: 10, unit_cost: 4500 } ], supplier: discounting)

        invoice = result.record
        expect(invoice.early_payment_discount_percentage).to eq(5)
        expect(invoice.amount_with_discount).to eq(42_750)
      end
    end
  end
end
