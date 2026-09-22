require 'rails_helper'

RSpec::Matchers.define_negated_matcher :not_change, :change

RSpec.describe Sales::CancelOrder do
  let(:user) { create(:user) }
  let(:customer) { create(:customer, customer_type: "workshop", has_credit_account: true) }
  let(:product) { create(:product, current_stock: 0, price_unit: 100) }
  let(:stock_location) { create(:stock_location) }

  def stock!(product, quantity)
    create(:stock_movement, product: product, stock_location: stock_location, quantity: quantity, movement_type: "purchase")
    product.recalculate_current_stock!
  end

  before do
    stock_location
    stock!(product, 50)
  end

  describe '.call' do
    context 'with valid confirmed order' do
      let(:order) do
        result = Sales::CreateOrder.call(
          customer: customer,
          items: [ { product_id: product.id, quantity: 5, unit_price: 100 } ],
          order_type: 'immediate',
          paper_number: 'L-2001',
          user: user
        )
        result.record
      end

      it 'cancels order successfully' do
        result = described_class.call(order: order, user: user)

        expect(result.success?).to be true
        expect(result.record).to eq(order)
        expect(result.record.status).to eq('cancelled')
        expect(result.errors).to be_empty
      end

      it 'clears settled_on so a cancelled order no longer shows a collected date' do
        order.update!(settled_on: Date.current)

        described_class.call(order: order, user: user)

        expect(order.reload.settled_on).to be_nil
      end

      it 'puts back on the shelf what the sale took' do
        order
        expect(product.reload.current_stock).to eq(45)

        expect {
          described_class.call(order: order, user: user)
        }.to change { product.reload.current_stock }.from(45).to(50)
      end

      it 'writes one positive adjustment per line, referencing the line' do
        described_class.call(order: order, user: user)

        restore = StockMovement.where(movement_type: 'adjustment').last
        expect(restore.product).to eq(product)
        expect(restore.quantity).to eq(5)
        expect(restore.reference).to eq(order.order_items.first)
        expect(order.order_items.first.stock_movements.sum(:quantity)).to eq(0)
      end

      it 'accepts reason parameter' do
        result = described_class.call(order: order, user: user, reason: 'Customer requested cancellation')

        expect(result.success?).to be true
        expect(StockMovement.where(movement_type: 'adjustment').last.note).to eq('Customer requested cancellation')
      end

      it 'names the note when no reason is given' do
        described_class.call(order: order, user: user)

        expect(StockMovement.where(movement_type: 'adjustment').last.note).to eq("Cancelación nota L-2001")
      end

      it 'names the note when the reason is blank' do
        described_class.call(order: order, user: user, reason: '')

        expect(StockMovement.where(movement_type: 'adjustment').last.note).to eq("Cancelación nota L-2001")
      end

      it 'gives back only what the floor let the sale take' do
        product.stock_movements.destroy_all
        stock!(product, 2)
        order
        expect(product.reload.current_stock).to eq(0)

        described_class.call(order: order, user: user)

        expect(product.reload.current_stock).to eq(2)
      end
    end

    context 'with credit order' do
      let(:credit_order) do
        result = Sales::CreateOrder.call(
          customer: customer,
          items: [ { product_id: product.id, quantity: 5, unit_price: 100 } ],
          order_type: 'credit',
          paper_number: 'L-2002',
          user: user
        )
        result.record
      end

      it 'reduces customer balance when cancelled' do
        credit_order # Create order (balance = 500)
        expect(customer.current_balance).to eq(500)

        described_class.call(order: credit_order, user: user)

        expect(customer.reload.current_balance).to eq(0)
      end

      it 'destroys the PaymentAllocations for the cancelled order' do
        order_with_payment = Sales::CreateOrder.call(
          customer: customer,
          items: [ { product_id: product.id, quantity: 5, unit_price: 100 } ],
          order_type: 'credit',
          paper_number: 'L-2003',
          user: user
        ).record
        Payments::AllocatePayment.call(
          user: user,
          customer: customer,
          payment_date: Date.current,
          allocations: [ { order_id: order_with_payment.id, amount: 200, payment_method: 'cash' } ]
        )
        expect(order_with_payment.payment_allocations.count).to eq(1)

        described_class.call(order: order_with_payment, user: user)

        expect(order_with_payment.reload.payment_allocations.count).to eq(0)
      end

      it 'keeps the Payment record alive as the anchor of its cash movements' do
        order_with_payment = Sales::CreateOrder.call(
          customer: customer,
          items: [ { product_id: product.id, quantity: 5, unit_price: 100 } ],
          order_type: 'credit',
          paper_number: 'L-2004',
          user: user
        ).record
        Payments::AllocatePayment.call(
          user: user,
          customer: customer,
          payment_date: Date.current,
          allocations: [ { order_id: order_with_payment.id, amount: 200, payment_method: 'cash' } ]
        )
        payment_id = order_with_payment.payment_allocations.first.payment_id

        described_class.call(order: order_with_payment, user: user)

        expect(Payment.find_by(id: payment_id)).to be_present
      end
    end

    context 'cash reversal' do
      def credit_order(paper_number, amount: 500)
        Sales::CreateOrder.call(
          customer: customer,
          items: [ { product_id: product.id, quantity: amount / 100, unit_price: 100 } ],
          order_type: 'credit',
          paper_number: paper_number,
          user: user
        ).record
      end

      def collect(rows)
        result = Payments::AllocatePayment.call(
          user: user,
          customer: customer,
          payment_date: Date.current,
          allocations: rows
        )
        raise result.errors.to_sentence if result.failure?

        result.record.first
      end

      it 'writes the reversing movement and leaves the original untouched' do
        order = credit_order('L-3001')
        payment = collect([ { order_id: order.id, amount: 200, payment_method: 'cash' } ])
        original = CashMovement.find_by!(source_payment_id: payment.id)

        expect {
          expect(described_class.call(order: order, user: user).success?).to be true
        }.to change { CashMovement.where(source_payment_id: payment.id).count }.from(1).to(2)

        reversal = CashMovement.where(source_payment_id: payment.id).order(:id).last
        expect(reversal.amount).to eq(-original.amount)
        expect(reversal.account).to eq(original.account)
        expect(reversal.channel).to eq(original.channel)
        expect(reversal.user).to eq(user)
        expect(original.reload.amount).to eq(200)
        expect(CashMovement.where(source_payment_id: payment.id).sum(:amount)).to eq(0)
      end

      it 'writes nothing when the order was never collected' do
        order = credit_order('L-3002')

        expect {
          expect(described_class.call(order: order, user: user).success?).to be true
        }.not_to change { CashMovement.count }
      end

      it 'leaves a payment shared with another order alone' do
        cancelled = credit_order('L-3003')
        surviving = credit_order('L-3004')
        payment = collect([
          { order_id: cancelled.id, amount: 200, payment_method: 'cash' },
          { order_id: surviving.id, amount: 300, payment_method: 'cash' }
        ])

        expect {
          expect(described_class.call(order: cancelled, user: user).success?).to be true
        }.not_to change { CashMovement.where(source_payment_id: payment.id).count }

        expect(Payment.find_by(id: payment.id)).to be_present
        expect(surviving.reload.payment_allocations.sum(:amount)).to eq(300)
        expect(cancelled.reload.payment_allocations).to be_empty
      end

      it 'rolls the whole cancellation back when the reversal fails' do
        order = credit_order('L-3005')
        payment = collect([ { order_id: order.id, amount: 200, payment_method: 'cash' } ])
        allow(Cash::ReversePayment).to receive(:call).and_return(
          Result.new(success?: false, record: nil, errors: [ 'Este cobro ya fue revertido' ])
        )

        result = described_class.call(order: order, user: user)

        expect(result.success?).to be false
        expect(result.errors).to include('Este cobro ya fue revertido')
        expect(order.reload.status).to eq('pending')
        expect(order.payment_allocations.count).to eq(1)
        expect(product.reload.current_stock).to eq(45)
        expect(order.sale_movements.sum(:quantity)).to eq(-5)
        expect(CashMovement.where(source_payment_id: payment.id).count).to eq(1)
      end
    end

    context 'with multiple items' do
      before { stock!(product2, 30) }

      let(:product2) { create(:product, current_stock: 0, price_unit: 50) }
      let(:multi_item_order) do
        result = Sales::CreateOrder.call(
          customer: customer,
          items: [
            { product_id: product.id, quantity: 3, unit_price: 100 },
            { product_id: product2.id, quantity: 2, unit_price: 50 }
          ],
          order_type: 'immediate',
          paper_number: 'L-2005',
          user: user
        )
        result.record
      end

      it 'restores stock for all products' do
        multi_item_order

        expect {
          described_class.call(order: multi_item_order, user: user)
        }.to change { product.reload.current_stock }.by(3)
          .and change { product2.reload.current_stock }.by(2)
      end

      it 'writes one adjustment per line' do
        multi_item_order

        expect {
          described_class.call(order: multi_item_order, user: user)
        }.to change { StockMovement.where(movement_type: 'adjustment').count }.by(2)
      end
    end

    context 'on_account with a partial delivery' do
      let(:kept)  { create(:product, current_stock: 0, price_unit: 100) }
      let(:taken) { create(:product, current_stock: 0, price_unit: 100) }

      it 'gives back only the lines that were delivered' do
        stock!(kept, 5)
        stock!(taken, 5)
        order = Sales::CreateOrder.call(
          customer: Customer.mostrador, order_type: 'on_account', paper_number: 'OA-9',
          contact_name: 'Juan', contact_phone: '11 5555 1234', user: user,
          items: [ { product_id: taken.id, quantity: 2, unit_price: 100 },
                   { product_id: kept.id, quantity: 2, unit_price: 100 } ],
          delivered_product_ids: [ taken.id ]
        ).record
        expect(taken.reload.current_stock).to eq(3)

        expect(described_class.call(order: order, user: user).success?).to be true

        expect(taken.reload.current_stock).to eq(5)
        expect(kept.reload.current_stock).to eq(5)
        expect(StockMovement.where(movement_type: 'adjustment').count).to eq(1)
      end

      it 'gives nothing back for a line whose delivery was undone' do
        stock!(kept, 5)
        order = Sales::CreateOrder.call(
          customer: Customer.mostrador, order_type: 'on_account', paper_number: 'OA-10',
          contact_name: 'Juan', contact_phone: '11 5555 1234', user: user,
          items: [ { product_id: kept.id, quantity: 2, unit_price: 100 } ]
        ).record
        line = order.order_items.first

        Inventory::MarkDelivered.call(order: order, order_item_ids: [ line.id ], delivered: true)
        Inventory::MarkDelivered.call(order: order, order_item_ids: [ line.id ], delivered: false)
        expect(kept.reload.current_stock).to eq(5)

        expect {
          expect(described_class.call(order: order, user: user).success?).to be true
        }.to not_change(StockMovement, :count).and not_change { kept.reload.current_stock }
      end
    end

    context 'with already cancelled order' do
      let(:order) do
        result = Sales::CreateOrder.call(
          customer: customer,
          items: [ { product_id: product.id, quantity: 5, unit_price: 100 } ],
          order_type: 'immediate',
          paper_number: 'L-2006',
          user: user
        )
        result.record
      end

      before do
        described_class.call(order: order, user: user) # Cancel once
      end

      it 'returns failure result' do
        result = described_class.call(order: order, user: user)

        expect(result.success?).to be false
        expect(result.errors).to include('Order is already cancelled')
        expect(result.record).to be_nil
      end

      it 'does not create additional stock movements' do
        initial_count = StockMovement.count

        described_class.call(order: order, user: user)

        expect(StockMovement.count).to eq(initial_count)
      end

      it 'does not change product stock' do
        stock_after_first_cancel = product.reload.current_stock

        expect {
          described_class.call(order: order, user: user)
        }.not_to change { product.reload.current_stock }
      end
    end

    context 'error handling' do
      let(:order) do
        result = Sales::CreateOrder.call(
          customer: customer,
          items: [ { product_id: product.id, quantity: 5, unit_price: 100 } ],
          order_type: 'immediate',
          paper_number: 'L-2007',
          user: user
        )
        result.record
      end

      it 'logs errors on unexpected failures' do
        allow(order).to receive(:update!).and_raise(StandardError, 'Database error')

        expect(Rails.logger).to receive(:error).with(/Error in Sales::CancelOrder/)
        expect(Rails.logger).to receive(:error).with(kind_of(String)) # backtrace

        result = described_class.call(order: order, user: user)

        expect(result.success?).to be false
        expect(result.errors).to include('Error cancelling order')
      end
    end

    context 'transaction rollback' do
      let(:order) do
        result = Sales::CreateOrder.call(
          customer: customer,
          items: [ { product_id: product.id, quantity: 5, unit_price: 100 } ],
          order_type: 'immediate',
          paper_number: 'L-2008',
          user: user
        )
        result.record
      end

      it 'rolls back order status change if the stock restore fails' do
        initial_status = order.status

        allow(Inventory::RestoreLineStock).to receive(:call).and_return(
          Result.new(success?: false, record: nil, errors: [ 'Stock adjustment failed' ])
        )

        result = described_class.call(order: order, user: user)

        expect(result.success?).to be false
        expect(order.reload.status).to eq(initial_status)
      end
    end
  end
end
