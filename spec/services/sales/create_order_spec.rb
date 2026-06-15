require 'rails_helper'

RSpec.describe Sales::CreateOrder do
  let!(:stock_location) { create(:stock_location) }
  let(:customer_with_credit) { create(:customer, customer_type: "workshop", has_credit_account: true) }
  let(:customer_without_credit) { create(:customer, has_credit_account: false) }

  describe '.call' do
    context 'with valid immediate order' do
      let(:product) { create(:product, current_stock: 50, price_unit: 100) }

      it 'creates order successfully' do
        result = described_class.call(
          customer: customer_without_credit,
          items: [ { product_id: product.id, quantity: 2, unit_price: 100 } ],
          order_type: 'immediate',
          paper_number: '0001'
        )

        expect(result.success?).to be true
        expect(result.record).to be_a(Order)
        expect(result.record.order_type).to eq('immediate')
        expect(result.record.status).to eq('pending')
        expect(result.errors).to be_empty
      end

      it 'calculates total correctly' do
        result = described_class.call(
          customer: customer_without_credit,
          items: [ { product_id: product.id, quantity: 2, unit_price: 100 } ],
          order_type: 'immediate',
          paper_number: '0001'
        )

        expect(result.record.total_amount).to eq(200)
      end

      it 'creates order items' do
        result = described_class.call(
          customer: customer_without_credit,
          items: [ { product_id: product.id, quantity: 2, unit_price: 100 } ],
          order_type: 'immediate',
          paper_number: '0001'
        )

        expect(result.record.order_items.count).to eq(1)
        expect(result.record.order_items.first.product).to eq(product)
        expect(result.record.order_items.first.quantity).to eq(2)
        expect(result.record.order_items.first.unit_price).to eq(100)
      end

      it 'accepts channel parameter' do
        result = described_class.call(
          customer: customer_without_credit,
          items: [ { product_id: product.id, quantity: 2, unit_price: 100 } ],
          order_type: 'immediate',
          channel: 'whatsapp',
          paper_number: '0001'
        )

        expect(result.success?).to be true
        expect(result.record.channel).to eq('whatsapp')
      end

      it 'works with Customer.mostrador' do
        result = described_class.call(
          customer: Customer.mostrador,
          items: [ { product_id: product.id, quantity: 2, unit_price: 100 } ],
          order_type: 'immediate',
          paper_number: '0001'
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
          order_type: 'credit',
          paper_number: '0001'
        )

        expect(result.success?).to be true
        expect(result.record.order_type).to eq('credit')
        expect(result.record.customer).to eq(customer_with_credit)
      end

      it 'fails if customer does not have credit account' do
        result = described_class.call(
          customer: customer_without_credit,
          items: [ { product_id: product.id, quantity: 2, unit_price: 100 } ],
          order_type: 'credit',
          paper_number: '0001'
        )

        expect(result.success?).to be false
        expect(result.errors).to include('Customer does not have credit account enabled')
        expect(result.record).to be_nil
      end

      it 'increases customer balance for credit orders' do
        described_class.call(
          customer: customer_with_credit,
          items: [ { product_id: product.id, quantity: 2, unit_price: 100 } ],
          order_type: 'credit',
          paper_number: '0001'
        )

        expect(customer_with_credit.current_balance).to eq(200)
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
          order_type: 'immediate',
          paper_number: '0001'
        )

        expect(result.success?).to be true
        expect(result.record.order_items.count).to eq(2)
        expect(result.record.total_amount).to eq(350) # (2*100) + (3*50)
      end
    end

    context 'with manual pricing rules' do
      let(:product) { create(:product, current_stock: 50, price_unit: 100) }

      it 'rejects an item with zero unit_price' do
        result = described_class.call(
          customer: customer_without_credit,
          items: [ { product_id: product.id, quantity: 2, unit_price: 0 } ],
          order_type: 'immediate',
          paper_number: '0001'
        )

        expect(result.success?).to be false
        expect(result.errors).to include('El precio debe ser mayor a cero')
      end

      it 'rejects an item with nil unit_price' do
        result = described_class.call(
          customer: customer_without_credit,
          items: [ { product_id: product.id, quantity: 2, unit_price: nil } ],
          order_type: 'immediate',
          paper_number: '0001'
        )

        expect(result.success?).to be false
        expect(result.errors).to include('El precio debe ser mayor a cero')
      end

      it 'writes the entered price back to the product price_unit' do
        result = described_class.call(
          customer: customer_without_credit,
          items: [ { product_id: product.id, quantity: 2, unit_price: 175 } ],
          order_type: 'immediate',
          paper_number: '0001'
        )

        expect(result.success?).to be true
        expect(product.reload.price_unit).to eq(175)
      end

      it 'updates each product price_unit independently for multiple items' do
        product2 = create(:product, current_stock: 50, price_unit: 100)

        described_class.call(
          customer: customer_without_credit,
          items: [
            { product_id: product.id, quantity: 1, unit_price: 250 },
            { product_id: product2.id, quantity: 1, unit_price: 60 }
          ],
          order_type: 'immediate',
          paper_number: '0001'
        )

        expect(product.reload.price_unit).to eq(250)
        expect(product2.reload.price_unit).to eq(60)
      end
    end

    context 'with insufficient stock' do
      let(:product) { create(:product, current_stock: 50, price_unit: 100) }

      it 'returns failure result' do
        result = described_class.call(
          customer: customer_with_credit,
          items: [ { product_id: product.id, quantity: 100, unit_price: 100 } ],
          order_type: 'immediate',
          paper_number: '0001'
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
            order_type: 'immediate',
            paper_number: '0001'
          )
        }.not_to change(Order, :count)
      end

      it 'does not create order items' do
        expect {
          described_class.call(
            customer: customer_with_credit,
            items: [ { product_id: product.id, quantity: 100, unit_price: 100 } ],
            order_type: 'immediate',
            paper_number: '0001'
          )
        }.not_to change(OrderItem, :count)
      end

      it 'does not create stock movements' do
        expect {
          described_class.call(
            customer: customer_with_credit,
            items: [ { product_id: product.id, quantity: 100, unit_price: 100 } ],
            order_type: 'immediate',
            paper_number: '0001'
          )
        }.not_to change(StockMovement, :count)
      end

      it 'does not reduce product stock' do
        expect {
          described_class.call(
            customer: customer_with_credit,
            items: [ { product_id: product.id, quantity: 100, unit_price: 100 } ],
            order_type: 'immediate',
            paper_number: '0001'
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
          order_type: 'invalid',
          paper_number: '0001'
        )

        expect(result.success?).to be false
        expect(result.errors).to include('Invalid order type')
      end

      it 'fails with nil customer' do
        result = described_class.call(
          customer: nil,
          items: [ { product_id: product.id, quantity: 2, unit_price: 100 } ],
          order_type: 'immediate',
          paper_number: '0001'
        )

        expect(result.success?).to be false
        expect(result.errors).to include('Customer is required')
      end

      it 'fails with empty items' do
        result = described_class.call(
          customer: customer_with_credit,
          items: [],
          order_type: 'immediate',
          paper_number: '0001'
        )

        expect(result.success?).to be false
        expect(result.errors).to include('At least one product is required')
      end

      it 'fails with zero quantity' do
        result = described_class.call(
          customer: customer_with_credit,
          items: [ { product_id: product.id, quantity: 0, unit_price: 100 } ],
          order_type: 'immediate',
          paper_number: '0001'
        )

        expect(result.success?).to be false
        expect(result.errors).to include('Quantity must be greater than zero')
      end

      it 'fails with negative quantity' do
        result = described_class.call(
          customer: customer_with_credit,
          items: [ { product_id: product.id, quantity: -5, unit_price: 100 } ],
          order_type: 'immediate',
          paper_number: '0001'
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
          items: [ { product_id: product.id, quantity: 2, unit_price: 100 } ],
          order_type: 'immediate',
          source: 'from_paper',
          paper_number: '0045'
        )

        expect(result.success?).to be true
        expect(result.record.source).to eq('from_paper')
        expect(result.record.paper_number).to eq('0045')
      end

      it 'rejects nil unit_price even with from_paper source' do
        result = described_class.call(
          customer: customer_without_credit,
          items: [ { product_id: product.id, quantity: 2, unit_price: nil } ],
          order_type: 'immediate',
          source: 'from_paper',
          paper_number: '0001'
        )

        expect(result.success?).to be false
        expect(result.errors).to include('El precio debe ser mayor a cero')
      end

      it 'sets sale_date correctly' do
        sale_date = 1.week.ago.to_date
        result = described_class.call(
          customer: customer_without_credit,
          items: [ { product_id: product.id, quantity: 2, unit_price: 100 } ],
          order_type: 'immediate',
          source: 'from_paper',
          paper_number: '0001',
          sale_date: sale_date
        )

        expect(result.success?).to be true
        expect(result.record.sale_date).to eq(sale_date)
      end

      it 'skips stock validation (allows selling with zero stock)' do
        zero_stock_product = create(:product, current_stock: 0, price_unit: 100)

        result = described_class.call(
          customer: customer_without_credit,
          items: [ { product_id: zero_stock_product.id, quantity: 10, unit_price: 100 } ],
          order_type: 'immediate',
          source: 'from_paper',
          paper_number: '0001'
        )

        expect(result.success?).to be true
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
          order_type: 'immediate',
          paper_number: '0001'
        )

        expect(Order.count).to eq(initial_order_count)
        expect(OrderItem.count).to eq(initial_item_count)
        expect(StockMovement.count).to eq(initial_movement_count)
      end
    end

    context 'pending sale note semantics' do
      it 'creates an order in pending status with no payments or discount' do
        product = create(:product, current_stock: 10, price_unit: 100)
        customer = create(:customer, :with_credit)

        result = described_class.call(
          customer: customer,
          order_type: "credit",
          paper_number: "0001",
          items: [ { product_id: product.id, quantity: 2, unit_price: 100 } ]
        )

        expect(result).to be_success
        order = result.record
        expect(order.status).to eq("pending")
        expect(order.total_amount).to eq(200)
        expect(order.original_total_amount).to eq(200)
        expect(order.payment_allocations).to be_empty
        expect(order.order_items.first.discount_percent).to eq(0)
      end

      it "requires paper_number" do
        product = create(:product, current_stock: 5, price_unit: 100)
        customer = create(:customer, :with_credit)

        result = described_class.call(
          customer: customer,
          order_type: "credit",
          paper_number: nil,
          items: [ { product_id: product.id, quantity: 1, unit_price: 100 } ]
        )

        expect(result).to be_failure
        expect(result.errors.join).to match(/talonario|paper/i)
      end

      it "no longer accepts payments: keyword" do
        expect(described_class.method(:call).parameters.map(&:last)).not_to include(:payments)
      end

      it "no longer accepts discount_percent: keyword" do
        expect(described_class.method(:call).parameters.map(&:last)).not_to include(:discount_percent)
      end
    end
  end

  describe "on_account orders" do
    let(:product) { create(:product, current_stock: 10, price_unit: 100) }

    it "creates a pending on_account order with contact and initial delivery" do
      result = described_class.call(
        customer: Customer.mostrador,
        order_type: "on_account",
        paper_number: "OA-001",
        contact_name: "Juan Pérez",
        contact_phone: "11 5555 1234",
        items: [ { product_id: product.id, quantity: 2, unit_price: 100 } ],
        delivered_product_ids: [ product.id ]
      )

      expect(result).to be_success
      order = result.record
      expect(order.on_account_order_type?).to be(true)
      expect(order.status).to eq("pending")
      expect(order.contact_name).to eq("Juan Pérez")
      expect(order.contact_phone).to eq("11 5555 1234")
      expect(order.order_items.first.delivered_at).to be_present
    end

    it "leaves items undelivered when not in delivered_product_ids" do
      result = described_class.call(
        customer: Customer.mostrador,
        order_type: "on_account",
        paper_number: "OA-002",
        contact_name: "Ana",
        contact_phone: "11 0000 0000",
        items: [ { product_id: product.id, quantity: 1, unit_price: 100 } ],
        delivered_product_ids: []
      )

      expect(result).to be_success
      expect(result.record.order_items.first.delivered_at).to be_nil
    end

    it "fails when contact is missing" do
      result = described_class.call(
        customer: Customer.mostrador,
        order_type: "on_account",
        paper_number: "OA-003",
        contact_name: nil,
        contact_phone: nil,
        items: [ { product_id: product.id, quantity: 1, unit_price: 100 } ]
      )

      expect(result).to be_failure
      expect(result.errors).to include(a_string_matching(/contacto/i))
    end
  end
end
