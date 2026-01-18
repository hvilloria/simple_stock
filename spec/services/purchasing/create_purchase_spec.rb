# frozen_string_literal: true

require "rails_helper"

RSpec.describe Purchasing::CreatePurchase do
  let(:supplier) { create(:supplier) }
  let(:product1) { create(:product, current_stock: 0, cost_unit: 0, cost_currency: "USD") }
  let(:product2) { create(:product, current_stock: 0, cost_unit: 0, cost_currency: "USD") }
  let!(:stock_location) { create(:stock_location) }

  describe ".call" do
    context "with valid USD purchase" do
      let(:items) do
        [
          { product_id: product1.id, quantity: 50, unit_cost: 30.0 },
          { product_id: product2.id, quantity: 20, unit_cost: 45.0 }
        ]
      end

      it "creates purchase successfully" do
        result = described_class.call(
          supplier: supplier,
          items: items,
          currency: "USD",
          exchange_rate: 1200
        )

        expect(result.success?).to be true
        expect(result.record).to be_a(Purchase)
        expect(result.record.currency).to eq("USD")
        expect(result.record.exchange_rate).to eq(1200)
      end

      it "creates purchase items" do
        result = described_class.call(
          supplier: supplier,
          items: items,
          currency: "USD",
          exchange_rate: 1200
        )

        expect(result.record.purchase_items.count).to eq(2)
      end

      it "increases product stock" do
        # Initialize stock for products
        create(:stock_movement, product: product1, stock_location: stock_location, quantity: 0)
        create(:stock_movement, product: product2, stock_location: stock_location, quantity: 0)
        product1.recalculate_current_stock!
        product2.recalculate_current_stock!

        expect do
          described_class.call(
            supplier: supplier,
            items: items,
            currency: "USD",
            exchange_rate: 1200
          )
        end.to change { product1.reload.current_stock }.by(50)
           .and change { product2.reload.current_stock }.by(20)
      end

      it "creates stock movements" do
        expect do
          described_class.call(
            supplier: supplier,
            items: items,
            currency: "USD",
            exchange_rate: 1200
          )
        end.to change(StockMovement, :count).by(2)
      end

      it "updates product costs" do
        described_class.call(
          supplier: supplier,
          items: [ { product_id: product1.id, quantity: 10, unit_cost: 50.0 } ],
          currency: "USD",
          exchange_rate: 1200
        )

        expect(product1.reload.cost_unit).to eq(50.0)
        expect(product1.cost_currency).to eq("USD")
      end

      it "calculates total cost correctly" do
        result = described_class.call(
          supplier: supplier,
          items: items,
          currency: "USD",
          exchange_rate: 1200
        )

        # (50 × 30) + (20 × 45) = 1500 + 900 = 2400
        expect(result.record.total_cost).to eq(2400.0)
      end

      it "creates stock movements with polymorphic reference" do
        result = described_class.call(
          supplier: supplier,
          items: [ { product_id: product1.id, quantity: 10, unit_cost: 50.0 } ],
          currency: "USD",
          exchange_rate: 1200
        )

        movement = StockMovement.last
        expect(movement.reference).to eq(result.record)
        expect(movement.reference_type).to eq("Purchase")
        expect(movement.reference_id).to eq(result.record.id)
      end
    end

    context "with ARS purchase" do
      it "creates purchase without exchange_rate" do
        result = described_class.call(
          supplier: supplier,
          items: [ { product_id: product1.id, quantity: 10, unit_cost: 60000 } ],
          currency: "ARS"
        )

        expect(result.success?).to be true
        expect(result.record.currency).to eq("ARS")
        expect(result.record.exchange_rate).to be_nil
      end

      it "updates product cost in USD (converts from ARS)" do
        result = described_class.call(
          supplier: supplier,
          items: [ { product_id: product1.id, quantity: 10, unit_cost: 60000 } ],
          currency: "ARS",
          exchange_rate: 1200
        )

        # 60000 ARS / 1200 = 50 USD
        expect(product1.reload.cost_unit).to eq(50.0)
        expect(product1.cost_currency).to eq("USD")
      end
    end

    context "with custom purchase_date and notes" do
      it "uses provided purchase_date" do
        custom_date = Date.new(2024, 1, 15)
        result = described_class.call(
          supplier: supplier,
          items: [ { product_id: product1.id, quantity: 10, unit_cost: 50 } ],
          currency: "USD",
          exchange_rate: 1200,
          purchase_date: custom_date
        )

        expect(result.record.purchase_date).to eq(custom_date)
      end

      it "uses today as default purchase_date" do
        result = described_class.call(
          supplier: supplier,
          items: [ { product_id: product1.id, quantity: 10, unit_cost: 50 } ],
          currency: "USD",
          exchange_rate: 1200
        )

        expect(result.record.purchase_date).to eq(Date.today)
      end

      it "saves notes" do
        result = described_class.call(
          supplier: supplier,
          items: [ { product_id: product1.id, quantity: 10, unit_cost: 50 } ],
          currency: "USD",
          exchange_rate: 1200,
          notes: "Compra urgente"
        )

        expect(result.record.notes).to eq("Compra urgente")
      end
    end

    context "with invalid params" do
      it "fails without exchange_rate for USD" do
        result = described_class.call(
          supplier: supplier,
          items: [ { product_id: product1.id, quantity: 10, unit_cost: 50 } ],
          currency: "USD",
          exchange_rate: nil
        )

        expect(result.success?).to be false
        expect(result.errors).to include(/Exchange rate required/)
      end

      it "fails with zero exchange_rate for USD" do
        result = described_class.call(
          supplier: supplier,
          items: [ { product_id: product1.id, quantity: 10, unit_cost: 50 } ],
          currency: "USD",
          exchange_rate: 0
        )

        expect(result.success?).to be false
        expect(result.errors).to include(/Exchange rate required/)
      end

      it "fails with invalid currency" do
        result = described_class.call(
          supplier: supplier,
          items: [ { product_id: product1.id, quantity: 10, unit_cost: 50 } ],
          currency: "EUR"
        )

        expect(result.success?).to be false
        expect(result.errors).to include(/Invalid currency/)
      end

      it "fails with empty items" do
        result = described_class.call(
          supplier: supplier,
          items: [],
          currency: "USD",
          exchange_rate: 1200
        )

        expect(result.success?).to be false
        expect(result.errors.first).to eq("At least one product is required")
      end

      it "fails with non-existent product" do
        result = described_class.call(
          supplier: supplier,
          items: [ { product_id: 99999, quantity: 10, unit_cost: 50 } ],
          currency: "USD",
          exchange_rate: 1200
        )

        expect(result.success?).to be false
        expect(result.errors).to include(/not found/)
      end

      it "fails without supplier" do
        result = described_class.call(
          supplier: nil,
          items: [ { product_id: product1.id, quantity: 10, unit_cost: 50 } ],
          currency: "USD",
          exchange_rate: 1200
        )

        expect(result.success?).to be false
        expect(result.errors).to include(/Supplier is required/)
      end

      it "fails with zero quantity" do
        result = described_class.call(
          supplier: supplier,
          items: [ { product_id: product1.id, quantity: 0, unit_cost: 50 } ],
          currency: "USD",
          exchange_rate: 1200
        )

        expect(result.success?).to be false
        expect(result.errors).to include(/greater than zero/)
      end

      it "fails with negative unit_cost" do
        result = described_class.call(
          supplier: supplier,
          items: [ { product_id: product1.id, quantity: 10, unit_cost: -50 } ],
          currency: "USD",
          exchange_rate: 1200
        )

        expect(result.success?).to be false
        expect(result.errors).to include(/greater than or equal to zero/)
      end
    end

    context "when transaction fails" do
      it "does not create purchase" do
        allow_any_instance_of(Purchase).to receive(:save!).and_raise(StandardError, "DB error")

        expect do
          described_class.call(
            supplier: supplier,
            items: [ { product_id: product1.id, quantity: 10, unit_cost: 50 } ],
            currency: "USD",
            exchange_rate: 1200
          )
        end.not_to change(Purchase, :count)
      end

      it "does not create stock movements" do
        allow_any_instance_of(Purchase).to receive(:save!).and_raise(StandardError, "DB error")

        expect do
          described_class.call(
            supplier: supplier,
            items: [ { product_id: product1.id, quantity: 10, unit_cost: 50 } ],
            currency: "USD",
            exchange_rate: 1200
          )
        end.not_to change(StockMovement, :count)
      end

      it "does not modify product stock" do
        initial_stock = product1.current_stock

        allow_any_instance_of(Purchase).to receive(:save!).and_raise(StandardError, "DB error")

        described_class.call(
          supplier: supplier,
          items: [ { product_id: product1.id, quantity: 10, unit_cost: 50 } ],
          currency: "USD",
          exchange_rate: 1200
        )

        expect(product1.reload.current_stock).to eq(initial_stock)
      end
    end
  end
end
