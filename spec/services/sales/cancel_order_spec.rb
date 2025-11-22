require 'rails_helper'

RSpec.describe Sales::CancelOrder do
  let(:customer) { create(:customer, has_credit_account: true) }
  let(:product) { create(:product, current_stock: 50, price_unit: 100) }
  let(:stock_location) { create(:stock_location) }

  before do
    stock_location
  end

  describe '.call' do
    context 'with valid confirmed order' do
      let(:order) do
        result = Sales::CreateOrder.call(
          customer: customer,
          items: [ { product_id: product.id, quantity: 5, unit_price: 100 } ],
          order_type: 'cash'
        )
        result.record
      end

      it 'cancels order successfully' do
        result = described_class.call(order: order)

        expect(result.success?).to be true
        expect(result.record).to eq(order)
        expect(result.record.status).to eq('cancelled')
        expect(result.errors).to be_empty
      end

      it 'restores product stock' do
        order # Create order first (reduces stock by 5)
        initial_stock = product.reload.current_stock

        expect {
          described_class.call(order: order)
        }.to change { product.reload.current_stock }.by(5)
      end

      it 'creates positive stock movements' do
        order # Create order first

        result = described_class.call(order: order)

        # Find the adjustment movement (last one created)
        adjustment_movement = StockMovement.where(movement_type: 'adjustment').last
        expect(adjustment_movement.product).to eq(product)
        expect(adjustment_movement.quantity).to eq(5) # Positive (reversal)
      end

      it 'accepts reason parameter' do
        result = described_class.call(
          order: order,
          reason: 'Customer requested cancellation'
        )

        expect(result.success?).to be true

        # Check the note in stock movement
        adjustment_movement = StockMovement.where(movement_type: 'adjustment').last
        expect(adjustment_movement.note).to eq('Customer requested cancellation')
      end

      it 'uses default reason when not provided' do
        result = described_class.call(order: order)

        adjustment_movement = StockMovement.where(movement_type: 'adjustment').last
        expect(adjustment_movement.note).to include("Order ##{order.id} cancellation")
      end
    end

    context 'with credit order' do
      let(:credit_order) do
        result = Sales::CreateOrder.call(
          customer: customer,
          items: [ { product_id: product.id, quantity: 5, unit_price: 100 } ],
          order_type: 'credit'
        )
        result.record
      end

      it 'reduces customer balance when cancelled' do
        credit_order # Create order (balance = 500)
        expect(customer.current_balance).to eq(500)

        described_class.call(order: credit_order)

        expect(customer.reload.current_balance).to eq(0)
      end
    end

    context 'with multiple items' do
      let(:product2) { create(:product, current_stock: 30, price_unit: 50) }
      let(:multi_item_order) do
        result = Sales::CreateOrder.call(
          customer: customer,
          items: [
            { product_id: product.id, quantity: 3, unit_price: 100 },
            { product_id: product2.id, quantity: 2, unit_price: 50 }
          ],
          order_type: 'cash'
        )
        result.record
      end

      it 'restores stock for all products' do
        multi_item_order # Create order

        expect {
          described_class.call(order: multi_item_order)
        }.to change { product.reload.current_stock }.by(3)
          .and change { product2.reload.current_stock }.by(2)
      end

      it 'creates adjustment movements for all items' do
        multi_item_order # Create order
        initial_count = StockMovement.where(movement_type: 'adjustment').count

        described_class.call(order: multi_item_order)

        expect(StockMovement.where(movement_type: 'adjustment').count).to eq(initial_count + 2)
      end
    end

    context 'with already cancelled order' do
      let(:order) do
        result = Sales::CreateOrder.call(
          customer: customer,
          items: [ { product_id: product.id, quantity: 5, unit_price: 100 } ],
          order_type: 'cash'
        )
        result.record
      end

      before do
        described_class.call(order: order) # Cancel once
      end

      it 'returns failure result' do
        result = described_class.call(order: order)

        expect(result.success?).to be false
        expect(result.errors).to include('Order is already cancelled')
        expect(result.record).to be_nil
      end

      it 'does not create additional stock movements' do
        initial_count = StockMovement.count

        described_class.call(order: order)

        expect(StockMovement.count).to eq(initial_count)
      end

      it 'does not change product stock' do
        stock_after_first_cancel = product.reload.current_stock

        expect {
          described_class.call(order: order)
        }.not_to change { product.reload.current_stock }
      end
    end

    context 'error handling' do
      let(:order) do
        result = Sales::CreateOrder.call(
          customer: customer,
          items: [ { product_id: product.id, quantity: 5, unit_price: 100 } ],
          order_type: 'cash'
        )
        result.record
      end

      it 'logs errors on unexpected failures' do
        allow(order).to receive(:update!).and_raise(StandardError, 'Database error')

        expect(Rails.logger).to receive(:error).with(/Error in Sales::CancelOrder/)
        expect(Rails.logger).to receive(:error).with(kind_of(String)) # backtrace

        result = described_class.call(order: order)

        expect(result.success?).to be false
        expect(result.errors).to include('Error cancelling order')
      end
    end

    context 'transaction rollback' do
      let(:order) do
        result = Sales::CreateOrder.call(
          customer: customer,
          items: [ { product_id: product.id, quantity: 5, unit_price: 100 } ],
          order_type: 'cash'
        )
        result.record
      end

      it 'rolls back order status change if stock adjustment fails' do
        initial_status = order.status

        allow(Inventory::AdjustStock).to receive(:call).and_return(
          Result.new(success?: false, record: nil, errors: [ 'Stock adjustment failed' ])
        )

        described_class.call(order: order)

        expect(order.reload.status).to eq(initial_status)
      end
    end
  end
end
