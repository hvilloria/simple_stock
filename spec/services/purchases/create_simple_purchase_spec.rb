require "rails_helper"

RSpec.describe Purchases::CreateSimplePurchase do
  let!(:supplier) { create(:supplier) }

  describe ".call" do
    context "with valid parameters" do
      it "creates a purchase in simple mode" do
        result = described_class.call(
          supplier: supplier,
          invoice_number: "FAC-001",
          amount: 5000,
          currency: "USD",
          exchange_rate: 1200,
          purchase_date: Date.today,
          due_date: 30.days.from_now,
          notes: "Test purchase"
        )

        expect(result.success?).to be true
        expect(result.record).to be_a(Purchase)
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

        purchase = result.record
        expect(purchase.supplier).to eq(supplier)
        expect(purchase.invoice_number).to eq("FAC-001")
        expect(purchase.amount).to eq(5000)
        expect(purchase.currency).to eq("USD")
        expect(purchase.exchange_rate).to eq(1200)
        expect(purchase.has_items).to be false
      end

      it "does not create purchase_items" do
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
        }.not_to change(PurchaseItem, :count)
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
        expect(result.errors).to include("Exchange rate required for USD purchases")
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
        expect(result.errors).to include("Exchange rate required for USD purchases")
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
          purchase_date: Date.today,
          due_date: 1.day.ago
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
  end
end
