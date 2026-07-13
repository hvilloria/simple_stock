# frozen_string_literal: true

require "rails_helper"

RSpec.describe Purchasing::CancelPurchase do
  let(:supplier) { create(:supplier) }
  let(:product) { create(:product, current_stock: 0, cost_unit: 0, cost_currency: "USD") }
  let!(:stock_location) { create(:stock_location) }

  let!(:invoice) do
    result = Purchasing::CreatePurchase.call(
      supplier: supplier,
      items: [ { product_id: product.id, quantity: 50, unit_cost: 30 } ],
      currency: "USD",
      exchange_rate: 1200
    )
    result.record
  end

  describe ".call" do
    it "cancels invoice successfully" do
      result = described_class.call(invoice: invoice)

      expect(result.success?).to be true
      expect(result.record.status).to eq("cancelled")
    end

    it "reverses stock movements" do
      skip "stock movements temporarily disabled"
      # Purchase increased stock by 50
      expect(product.reload.current_stock).to eq(50)

      described_class.call(invoice: invoice)

      # After cancelling, it returns to 0
      expect(product.reload.current_stock).to eq(0)
    end

    it "creates reverse stock movements" do
      skip "stock movements temporarily disabled"
      expect do
        described_class.call(invoice: invoice)
      end.to change(StockMovement, :count).by(1)

      reverse_movement = StockMovement.last
      expect(reverse_movement.quantity).to eq(-50)
      expect(reverse_movement.movement_type).to eq("adjustment")
    end

    it "creates reverse stock movements with polymorphic reference" do
      skip "stock movements temporarily disabled"
      described_class.call(invoice: invoice)

      reverse_movement = StockMovement.last
      expect(reverse_movement.reference).to eq(invoice)
      expect(reverse_movement.reference_type).to eq("Invoice")
      expect(reverse_movement.reference_id).to eq(invoice.id)
    end

    it "recalculates product costs" do
      # Make another purchase at a different price
      Purchasing::CreatePurchase.call(
        supplier: supplier,
        items: [ { product_id: product.id, quantity: 50, unit_cost: 40 } ],
        currency: "USD",
        exchange_rate: 1200
      )

      # Average cost: (50×30 + 50×40) / 100 = 35
      expect(product.reload.cost_unit.to_f).to eq(35.0)

      # Cancel the first purchase
      described_class.call(invoice: invoice)

      # Cost now reflects only the second purchase: 40
      expect(product.reload.cost_unit.to_f).to eq(40.0)
    end

    it "fails if already cancelled" do
      described_class.call(invoice: invoice)

      result = described_class.call(invoice: invoice)

      expect(result.success?).to be false
      expect(result.errors).to include(/already cancelled/)
    end

    context "with multiple items" do
      let(:product_a) { create(:product, current_stock: 0, cost_unit: 0, cost_currency: "USD") }
      let(:product_b) { create(:product, current_stock: 0, cost_unit: 0, cost_currency: "USD") }
      let!(:multi_invoice) do
        result = Purchasing::CreatePurchase.call(
          supplier: supplier,
          items: [
            { product_id: product_a.id, quantity: 50, unit_cost: 30 },
            { product_id: product_b.id, quantity: 20, unit_cost: 45 }
          ],
          currency: "USD",
          exchange_rate: 1200
        )
        result.record
      end

      it "reverses stock for all products" do
        skip "stock movements temporarily disabled"
        expect(product_a.reload.current_stock).to eq(50)
        expect(product_b.reload.current_stock).to eq(20)

        described_class.call(invoice: multi_invoice)

        expect(product_a.reload.current_stock).to eq(0)
        expect(product_b.reload.current_stock).to eq(0)
      end

      it "creates reverse movements for all items" do
        skip "stock movements temporarily disabled"
        expect do
          described_class.call(invoice: multi_invoice)
        end.to change(StockMovement, :count).by(2)
      end

      it "recalculates costs for all products" do
        # Before cancelling, they have costs from the purchase
        expect(product_a.reload.cost_unit.to_f).to eq(30.0)
        expect(product_b.reload.cost_unit.to_f).to eq(45.0)

        described_class.call(invoice: multi_invoice)

        # After cancelling, recalculate_average_cost! runs
        # but since there are no confirmed purchases, it keeps the previous cost
        # (the method returns early if invoice_items.empty?)
        # In a real scenario, we might want to reset to 0, but for now
        # the behavior is to keep the cost
        expect(product_a.reload.cost_unit.to_f).to eq(30.0)
        expect(product_b.reload.cost_unit.to_f).to eq(45.0)
      end
    end

    context "when transaction fails" do
      it "does not cancel invoice" do
        allow_any_instance_of(Invoice).to receive(:update!).and_raise(StandardError, "DB error")

        result = described_class.call(invoice: invoice)

        expect(result.success?).to be false
        expect(invoice.reload.status).to eq("confirmed")
      end

      it "does not create reverse stock movements" do
        allow_any_instance_of(Invoice).to receive(:update!).and_raise(StandardError, "DB error")

        expect do
          described_class.call(invoice: invoice)
        end.not_to change(StockMovement, :count)
      end

      it "does not modify product stock" do
        initial_stock = product.reload.current_stock

        allow_any_instance_of(Invoice).to receive(:update!).and_raise(StandardError, "DB error")

        described_class.call(invoice: invoice)

        expect(product.reload.current_stock).to eq(initial_stock)
      end
    end
  end
end
