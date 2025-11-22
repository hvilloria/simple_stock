# frozen_string_literal: true

require "rails_helper"

RSpec.describe Purchasing::CancelPurchase do
  let(:supplier) { create(:supplier) }
  let(:product) { create(:product, current_stock: 0, cost_unit: 0, cost_currency: "USD") }
  let!(:stock_location) { create(:stock_location) }

  let!(:purchase) do
    result = Purchasing::CreatePurchase.call(
      supplier: supplier,
      items: [ { product_id: product.id, quantity: 50, unit_cost: 30 } ],
      currency: "USD",
      exchange_rate: 1200
    )
    result.record
  end

  describe ".call" do
    it "cancels purchase successfully" do
      result = described_class.call(purchase: purchase)

      expect(result.success?).to be true
      expect(result.record.status).to eq("cancelled")
    end

    it "reverses stock movements" do
      # Purchase aumentó stock en 50
      expect(product.reload.current_stock).to eq(50)

      described_class.call(purchase: purchase)

      # Después de cancelar, vuelve a 0
      expect(product.reload.current_stock).to eq(0)
    end

    it "creates reverse stock movements" do
      expect do
        described_class.call(purchase: purchase)
      end.to change(StockMovement, :count).by(1)

      reverse_movement = StockMovement.last
      expect(reverse_movement.quantity).to eq(-50)
      expect(reverse_movement.movement_type).to eq("adjustment")
    end

    it "creates reverse stock movements with polymorphic reference" do
      described_class.call(purchase: purchase)

      reverse_movement = StockMovement.last
      expect(reverse_movement.reference).to eq(purchase)
      expect(reverse_movement.reference_type).to eq("Purchase")
      expect(reverse_movement.reference_id).to eq(purchase.id)
    end

    it "recalculates product costs" do
      # Hacer otra compra a diferente precio
      Purchasing::CreatePurchase.call(
        supplier: supplier,
        items: [ { product_id: product.id, quantity: 50, unit_cost: 40 } ],
        currency: "USD",
        exchange_rate: 1200
      )

      # Costo promedio: (50×30 + 50×40) / 100 = 35
      expect(product.reload.cost_unit.to_f).to eq(35.0)

      # Cancelar la primera compra
      described_class.call(purchase: purchase)

      # Costo ahora solo refleja la segunda compra: 40
      expect(product.reload.cost_unit.to_f).to eq(40.0)
    end

    it "fails if already cancelled" do
      described_class.call(purchase: purchase)

      result = described_class.call(purchase: purchase)

      expect(result.success?).to be false
      expect(result.errors).to include(/already cancelled/)
    end

    context "with multiple items" do
      let(:product_a) { create(:product, current_stock: 0, cost_unit: 0, cost_currency: "USD") }
      let(:product_b) { create(:product, current_stock: 0, cost_unit: 0, cost_currency: "USD") }
      let!(:multi_purchase) do
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
        expect(product_a.reload.current_stock).to eq(50)
        expect(product_b.reload.current_stock).to eq(20)

        described_class.call(purchase: multi_purchase)

        expect(product_a.reload.current_stock).to eq(0)
        expect(product_b.reload.current_stock).to eq(0)
      end

      it "creates reverse movements for all items" do
        expect do
          described_class.call(purchase: multi_purchase)
        end.to change(StockMovement, :count).by(2)
      end

      it "recalculates costs for all products" do
        # Antes de cancelar, tienen costos de la compra
        expect(product_a.reload.cost_unit.to_f).to eq(30.0)
        expect(product_b.reload.cost_unit.to_f).to eq(45.0)

        described_class.call(purchase: multi_purchase)

        # Después de cancelar, recalculate_average_cost! se ejecuta
        # pero como no hay compras confirmadas, mantiene el costo anterior
        # (el método hace return si purchase_items.empty?)
        # En un escenario real, podríamos querer resetear a 0, pero por ahora
        # el comportamiento es mantener el costo
        expect(product_a.reload.cost_unit.to_f).to eq(30.0)
        expect(product_b.reload.cost_unit.to_f).to eq(45.0)
      end
    end

    context "when transaction fails" do
      it "does not cancel purchase" do
        allow_any_instance_of(Purchase).to receive(:update!).and_raise(StandardError, "DB error")

        result = described_class.call(purchase: purchase)

        expect(result.success?).to be false
        expect(purchase.reload.status).to eq("confirmed")
      end

      it "does not create reverse stock movements" do
        allow_any_instance_of(Purchase).to receive(:update!).and_raise(StandardError, "DB error")

        expect do
          described_class.call(purchase: purchase)
        end.not_to change(StockMovement, :count)
      end

      it "does not modify product stock" do
        initial_stock = product.reload.current_stock

        allow_any_instance_of(Purchase).to receive(:update!).and_raise(StandardError, "DB error")

        described_class.call(purchase: purchase)

        expect(product.reload.current_stock).to eq(initial_stock)
      end
    end
  end
end
