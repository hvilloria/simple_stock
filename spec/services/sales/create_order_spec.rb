require 'rails_helper'

RSpec.describe Sales::CreateOrder do
  let!(:stock_location) { create(:stock_location) }
  let(:customer_with_credit) { create(:customer, has_credit_account: true) }
  let(:customer_without_credit) { create(:customer, has_credit_account: false) }

  describe '.call' do
    context 'with valid cash order' do
      let(:product) { create(:product, current_stock: 50, price_unit: 100) }

      it 'creates order successfully' do
        result = described_class.call(
          customer: customer_without_credit,
          items: [ { product_id: product.id, quantity: 2, unit_price: 100 } ],
          order_type: 'cash'
        )

        expect(result.success?).to be true
        expect(result.record).to be_a(Order)
        expect(result.record.order_type).to eq('cash')
        expect(result.record.status).to eq('confirmed')
        expect(result.errors).to be_empty
      end

      it 'calculates total correctly' do
        result = described_class.call(
          customer: customer_without_credit,
          items: [ { product_id: product.id, quantity: 2, unit_price: 100 } ],
          order_type: 'cash'
        )

        expect(result.record.total_amount).to eq(200)
      end

      it 'creates order items' do
        result = described_class.call(
          customer: customer_without_credit,
          items: [ { product_id: product.id, quantity: 2, unit_price: 100 } ],
          order_type: 'cash'
        )

        expect(result.record.order_items.count).to eq(1)
        expect(result.record.order_items.first.product).to eq(product)
        expect(result.record.order_items.first.quantity).to eq(2)
        expect(result.record.order_items.first.unit_price).to eq(100)
      end

      it 'reduces product stock' do
        test_product = create(:product, current_stock: 0, price_unit: 100)
        # Create initial stock movement
        create(:stock_movement, product: test_product, stock_location: stock_location, quantity: 50, movement_type: 'purchase')
        test_product.recalculate_current_stock!

        described_class.call(
          customer: customer_without_credit,
          items: [ { product_id: test_product.id, quantity: 2, unit_price: 100 } ],
          order_type: 'cash'
        )

        expect(test_product.reload.current_stock).to eq(48)
      end

      it 'creates negative stock movements' do
        result = described_class.call(
          customer: customer_without_credit,
          items: [ { product_id: product.id, quantity: 2, unit_price: 100 } ],
          order_type: 'cash'
        )

        movement = StockMovement.last
        expect(movement.product).to eq(product)
        expect(movement.quantity).to eq(-2)
        expect(movement.movement_type).to eq('sale')
      end

      it 'accepts channel parameter' do
        result = described_class.call(
          customer: customer_without_credit,
          items: [ { product_id: product.id, quantity: 2, unit_price: 100 } ],
          order_type: 'cash',
          channel: 'whatsapp'
        )

        expect(result.success?).to be true
        expect(result.record.channel).to eq('whatsapp')
      end

      it 'associates stock movements with order through polymorphic reference' do
        result = described_class.call(
          customer: customer_without_credit,
          items: [ { product_id: product.id, quantity: 2, unit_price: 100 } ],
          order_type: 'cash'
        )

        order = result.record
        expect(order.stock_movements.count).to eq(1)
        expect(order.stock_movements.first.reference).to eq(order)
        expect(order.stock_movements.first.reference_type).to eq('Order')
        expect(order.stock_movements.first.reference_id).to eq(order.id)
      end

      it 'works with Customer.mostrador' do
        result = described_class.call(
          customer: Customer.mostrador,
          items: [ { product_id: product.id, quantity: 2, unit_price: 100 } ],
          order_type: 'cash'
        )

        expect(result.success?).to be true
        expect(result.record.customer).to eq(Customer.mostrador)
      end
    end

    context 'with valid credit order' do
      let(:product) { create(:product, current_stock: 50, price_unit: 100) }

      it 'creates order successfully for customer with credit' do
        result = described_class.call(
          customer: customer_with_credit,
          items: [ { product_id: product.id, quantity: 2, unit_price: 100 } ],
          order_type: 'credit'
        )

        expect(result.success?).to be true
        expect(result.record.order_type).to eq('credit')
        expect(result.record.customer).to eq(customer_with_credit)
      end

      it 'increases customer balance for credit orders' do
        result = described_class.call(
          customer: customer_with_credit,
          items: [ { product_id: product.id, quantity: 2, unit_price: 100 } ],
          order_type: 'credit'
        )

        expect(customer_with_credit.current_balance).to eq(200)
      end

      it 'fails if customer does not have credit account' do
        result = described_class.call(
          customer: customer_without_credit,
          items: [ { product_id: product.id, quantity: 2, unit_price: 100 } ],
          order_type: 'credit'
        )

        expect(result.success?).to be false
        expect(result.errors).to include('Customer does not have credit account enabled')
        expect(result.record).to be_nil
      end
    end

    context 'with multiple items' do
      let(:product) { create(:product, current_stock: 50, price_unit: 100) }
      let(:product2) { create(:product, current_stock: 30, price_unit: 50) }

      it 'creates order with multiple items' do
        result = described_class.call(
          customer: customer_with_credit,
          items: [
            { product_id: product.id, quantity: 2, unit_price: 100 },
            { product_id: product2.id, quantity: 3, unit_price: 50 }
          ],
          order_type: 'cash'
        )

        expect(result.success?).to be true
        expect(result.record.order_items.count).to eq(2)
        expect(result.record.total_amount).to eq(350) # (2*100) + (3*50)
      end

      it 'reduces stock for all products' do
        test_product1 = create(:product, current_stock: 0, price_unit: 100)
        test_product2 = create(:product, current_stock: 0, price_unit: 50)
        # Create initial stock
        create(:stock_movement, product: test_product1, stock_location: stock_location, quantity: 50, movement_type: 'purchase')
        create(:stock_movement, product: test_product2, stock_location: stock_location, quantity: 30, movement_type: 'purchase')
        test_product1.recalculate_current_stock!
        test_product2.recalculate_current_stock!

        described_class.call(
          customer: customer_with_credit,
          items: [
            { product_id: test_product1.id, quantity: 2, unit_price: 100 },
            { product_id: test_product2.id, quantity: 3, unit_price: 50 }
          ],
          order_type: 'cash'
        )

        expect(test_product1.reload.current_stock).to eq(48)
        expect(test_product2.reload.current_stock).to eq(27)
      end
    end

    context 'with insufficient stock' do
      let(:product) { create(:product, current_stock: 50, price_unit: 100) }

      it 'returns failure result' do
        result = described_class.call(
          customer: customer_with_credit,
          items: [ { product_id: product.id, quantity: 100, unit_price: 100 } ],
          order_type: 'cash'
        )

        expect(result.success?).to be false
        expect(result.errors).to include(/Insufficient stock/)
        expect(result.record).to be_nil
      end

      it 'does not create order' do
        expect {
          described_class.call(
            customer: customer_with_credit,
            items: [ { product_id: product.id, quantity: 100, unit_price: 100 } ],
            order_type: 'cash'
          )
        }.not_to change(Order, :count)
      end

      it 'does not create order items' do
        expect {
          described_class.call(
            customer: customer_with_credit,
            items: [ { product_id: product.id, quantity: 100, unit_price: 100 } ],
            order_type: 'cash'
          )
        }.not_to change(OrderItem, :count)
      end

      it 'does not create stock movements' do
        expect {
          described_class.call(
            customer: customer_with_credit,
            items: [ { product_id: product.id, quantity: 100, unit_price: 100 } ],
            order_type: 'cash'
          )
        }.not_to change(StockMovement, :count)
      end

      it 'does not reduce product stock' do
        expect {
          described_class.call(
            customer: customer_with_credit,
            items: [ { product_id: product.id, quantity: 100, unit_price: 100 } ],
            order_type: 'cash'
          )
        }.not_to change { product.reload.current_stock }
      end
    end

    context 'with validation errors' do
      let(:product) { create(:product, current_stock: 50, price_unit: 100) }

      it 'fails with invalid order_type' do
        result = described_class.call(
          customer: customer_with_credit,
          items: [ { product_id: product.id, quantity: 2, unit_price: 100 } ],
          order_type: 'invalid'
        )

        expect(result.success?).to be false
        expect(result.errors).to include('Invalid order type')
      end

      it 'fails with nil customer' do
        result = described_class.call(
          customer: nil,
          items: [ { product_id: product.id, quantity: 2, unit_price: 100 } ],
          order_type: 'cash'
        )

        expect(result.success?).to be false
        expect(result.errors).to include('Customer is required')
      end

      it 'fails with empty items' do
        result = described_class.call(
          customer: customer_with_credit,
          items: [],
          order_type: 'cash'
        )

        expect(result.success?).to be false
        expect(result.errors).to include('At least one product is required')
      end

      it 'fails with zero quantity' do
        result = described_class.call(
          customer: customer_with_credit,
          items: [ { product_id: product.id, quantity: 0, unit_price: 100 } ],
          order_type: 'cash'
        )

        expect(result.success?).to be false
        expect(result.errors).to include('Quantity must be greater than zero')
      end

      it 'fails with negative quantity' do
        result = described_class.call(
          customer: customer_with_credit,
          items: [ { product_id: product.id, quantity: -5, unit_price: 100 } ],
          order_type: 'cash'
        )

        expect(result.success?).to be false
        expect(result.errors).to include('Quantity must be greater than zero')
      end
    end

    context 'with from_paper source' do
      let(:product) { create(:product, current_stock: 50, price_unit: 100) }

      it 'creates order with source from_paper' do
        result = described_class.call(
          customer: customer_without_credit,
          items: [ { product_id: product.id, quantity: 2, unit_price: 0 } ],
          order_type: 'cash',
          source: 'from_paper',
          paper_number: '0045'
        )

        expect(result.success?).to be true
        expect(result.record.source).to eq('from_paper')
        expect(result.record.paper_number).to eq('0045')
      end

      it 'allows total_amount = 0' do
        result = described_class.call(
          customer: customer_without_credit,
          items: [ { product_id: product.id, quantity: 2, unit_price: 0 } ],
          order_type: 'cash',
          source: 'from_paper'
        )

        expect(result.success?).to be true
        expect(result.record.total_amount).to eq(0)
      end

      it 'allows nil unit_price (uses product price or 0)' do
        result = described_class.call(
          customer: customer_without_credit,
          items: [ { product_id: product.id, quantity: 2, unit_price: nil } ],
          order_type: 'cash',
          source: 'from_paper'
        )

        expect(result.success?).to be true
        expect(result.record.order_items.first.unit_price).to eq(product.price_unit)
      end

      it 'sets sale_date correctly' do
        sale_date = 1.week.ago.to_date
        result = described_class.call(
          customer: customer_without_credit,
          items: [ { product_id: product.id, quantity: 2, unit_price: 100 } ],
          order_type: 'cash',
          source: 'from_paper',
          sale_date: sale_date
        )

        expect(result.success?).to be true
        expect(result.record.sale_date).to eq(sale_date)
      end

      it 'still validates stock' do
        low_stock_product = create(:product, current_stock: 1, price_unit: 100)

        result = described_class.call(
          customer: customer_without_credit,
          items: [ { product_id: low_stock_product.id, quantity: 10, unit_price: 0 } ],
          order_type: 'cash',
          source: 'from_paper'
        )

        expect(result.success?).to be false
        expect(result.errors).to include(/Insufficient stock/)
      end

      it 'still creates stock movements' do
        test_product = create(:product, current_stock: 0, price_unit: 100)
        create(:stock_movement, product: test_product, stock_location: stock_location, quantity: 50, movement_type: 'purchase')
        test_product.recalculate_current_stock!

        described_class.call(
          customer: customer_without_credit,
          items: [ { product_id: test_product.id, quantity: 2, unit_price: 0 } ],
          order_type: 'cash',
          source: 'from_paper'
        )

        expect(test_product.reload.current_stock).to eq(48)
      end
    end

    context 'transaction rollback' do
      it 'rolls back everything on stock validation error' do
        product_with_low_stock = create(:product, current_stock: 1)

        initial_order_count = Order.count
        initial_item_count = OrderItem.count
        initial_movement_count = StockMovement.count

        described_class.call(
          customer: customer_with_credit,
          items: [ { product_id: product_with_low_stock.id, quantity: 10, unit_price: 100 } ],
          order_type: 'cash'
        )

        expect(Order.count).to eq(initial_order_count)
        expect(OrderItem.count).to eq(initial_item_count)
        expect(StockMovement.count).to eq(initial_movement_count)
      end
    end
  end
end
