require "rails_helper"

RSpec.describe Invoices::CreateSimpleInvoice do
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
          purchase_date: Date.today,
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
          purchase_date: Date.today,
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
            purchase_date: Date.today,
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
            purchase_date: Date.today,
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
          purchase_date: Date.today,
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
          purchase_date: Date.today,
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
          purchase_date: Date.today,
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
          purchase_date: Date.today,
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
          purchase_date: Date.today,
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
          purchase_date: Date.today,
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
          purchase_date: Date.today,
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
          purchase_date: Date.today,
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
          purchase_date: Date.today,
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
        expect(result.record.purchase_date).to eq(Date.today)
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
          purchase_date: Date.today,
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
          purchase_date: Date.today,
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
  end
end
