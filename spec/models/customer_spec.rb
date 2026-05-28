require 'rails_helper'

RSpec.describe Customer, type: :model do
  describe 'associations' do
    it { should have_many(:orders).dependent(:nullify) }
    it { should have_many(:payments).dependent(:destroy) }
  end

  describe 'validations' do
    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:customer_type) }

    describe 'retail customers cannot have a credit account' do
      it 'is invalid when a retail customer has has_credit_account: true' do
        customer = build(:customer, customer_type: 'retail', has_credit_account: true)
        expect(customer).not_to be_valid
        expect(customer.errors[:has_credit_account]).to include('no puede estar habilitada para clientes minoristas')
      end

      it 'is valid when a retail customer does not have a credit account' do
        customer = build(:customer, customer_type: 'retail', has_credit_account: false)
        expect(customer).to be_valid
      end

      it 'is valid when a workshop customer has a credit account' do
        customer = build(:customer, :workshop)
        expect(customer).to be_valid
      end

      it 'is valid when a mechanic customer has a credit account' do
        customer = build(:customer, :mechanic)
        expect(customer).to be_valid
      end

      it 'is valid when a store customer has a credit account' do
        customer = build(:customer, :store)
        expect(customer).to be_valid
      end
    end
  end

  describe 'enums' do
    it 'defines customer_type enum with correct values' do
      expect(Customer.customer_types).to eq({
        'retail' => 'retail',
        'workshop' => 'workshop',
        'mechanic' => 'mechanic',
        'store' => 'store'
      })
    end

    it 'supports customer_type suffix methods' do
      customer = Customer.new(customer_type: 'workshop')
      expect(customer.workshop_customer_type?).to be true
      expect(customer.retail_customer_type?).to be false
    end
  end

  describe 'scopes' do
    let!(:retail_customer) { create(:customer, customer_type: 'retail') }
    let!(:retail_customer_no_credit) { create(:customer, customer_type: 'retail') }
    let!(:workshop_customer) { create(:customer, :workshop) }
    let!(:mechanic_customer) { create(:customer, :mechanic) }
    let!(:store_customer) { create(:customer, :store) }

    describe '.with_credit_account' do
      it 'returns only customers with credit account' do
        expect(Customer.with_credit_account).to contain_exactly(workshop_customer, mechanic_customer, store_customer)
      end
    end

    describe '.retail' do
      it 'returns only retail customers' do
        expect(Customer.retail).to include(retail_customer, retail_customer_no_credit)
      end
    end

    describe '.workshops' do
      it 'returns only workshop customers' do
        expect(Customer.workshops).to contain_exactly(workshop_customer)
      end
    end

    describe '.mechanics' do
      it 'returns only mechanic customers' do
        expect(Customer.mechanics).to contain_exactly(mechanic_customer)
      end
    end

    describe '.stores' do
      it 'returns only store customers' do
        expect(Customer.stores).to contain_exactly(store_customer)
      end
    end
  end

  describe '.mostrador' do
    it 'returns the generic counter customer' do
      customer = Customer.mostrador
      expect(customer.name).to eq('Cliente Mostrador')
      expect(customer.has_credit_account).to be false
      expect(customer.customer_type).to eq('retail')
    end

    it 'reuses the same customer on multiple calls' do
      customer1 = Customer.mostrador
      customer2 = Customer.mostrador
      expect(customer1.id).to eq(customer2.id)
    end

    it 'is persisted to the database' do
      customer = Customer.mostrador
      expect(customer).to be_persisted
    end
  end

  describe '#current_balance' do
    let(:customer) { create(:customer, :workshop) }

    context 'when customer does not have credit account' do
      let(:retail_customer) { create(:customer, has_credit_account: false) }

      it 'returns zero' do
        expect(retail_customer.current_balance).to eq(0)
      end
    end

    context 'when customer has credit account' do
      context 'with no orders or payments' do
        it 'returns zero' do
          expect(customer.current_balance).to eq(0)
        end
      end

      context 'with credit orders' do
        before do
          create(:order, customer: customer, order_type: 'credit', status: 'confirmed', total_amount: 1000)
          create(:order, customer: customer, order_type: 'credit', status: 'confirmed', total_amount: 500)
        end

        it 'calculates total from credit orders' do
          expect(customer.current_balance).to eq(1500)
        end
      end

      context 'with cancelled orders' do
        before do
          create(:order, customer: customer, order_type: 'credit', status: 'confirmed', total_amount: 1000)
          create(:order, customer: customer, order_type: 'credit', status: 'cancelled', total_amount: 500)
        end

        it 'excludes cancelled orders from balance' do
          expect(customer.current_balance).to eq(1000)
        end
      end

      context 'with immediate orders' do
        before do
          create(:order, customer: customer, order_type: 'immediate', status: 'confirmed', total_amount: 1000)
        end

        it 'does not include immediate orders in balance' do
          expect(customer.current_balance).to eq(0)
        end
      end

      context 'with payments' do
        let!(:credit_order) do
          create(:order, customer: customer, order_type: 'credit', status: 'confirmed', total_amount: 10000)
        end

        it 'subtracts payments allocated to credit orders' do
          payment = create(:payment, customer: customer, amount: 3000)
          create(:payment_allocation, payment: payment, order: credit_order, amount: 3000)
          expect(customer.current_balance).to eq(7000)
        end

        it 'handles multiple allocated payments' do
          p1 = create(:payment, customer: customer, amount: 3000)
          p2 = create(:payment, customer: customer, amount: 2000)
          create(:payment_allocation, payment: p1, order: credit_order, amount: 3000)
          create(:payment_allocation, payment: p2, order: credit_order, amount: 2000)
          expect(customer.current_balance).to eq(5000)
        end

        it 'ignores unallocated payments (they have no effect on the balance)' do
          # Under the allocation-aware balance, only allocations count.
          # A payment with no allocation has zero effect on the customer balance.
          create(:payment, customer: customer, amount: 12000)
          expect(customer.current_balance).to eq(10000)
        end
      end

      context 'with credit orders and payments' do
        before do
          order1 = create(:order, customer: customer, order_type: 'credit', status: 'confirmed', total_amount: 10000)
          create(:order, customer: customer, order_type: 'credit', status: 'confirmed', total_amount: 5000)
          payment = create(:payment, customer: customer, amount: 3000)
          create(:payment_allocation, payment: payment, order: order1, amount: 3000)
        end

        it 'calculates balance correctly' do
          # 10000 + 5000 - 3000 = 12000
          expect(customer.current_balance).to eq(12000)
        end
      end
    end
  end

  describe '.with_outstanding_balance' do
    let!(:stock_location) { create(:stock_location) }
    let(:product) { create(:product, current_stock: 50, price_unit: 100) }

    let(:debtor) { create(:customer, :with_credit) }
    let(:paid_up) { create(:customer, :with_credit) }
    let(:no_credit) { create(:customer, has_credit_account: false) }

    before do
      # debtor: confirmed credit order of $200, no allocations
      create(:order, :credit_order,
             customer: debtor, total_amount: 200, original_total_amount: 200)

      # paid_up: confirmed credit order of $100, fully allocated
      paid_order = create(:order, :credit_order,
                          customer: paid_up, total_amount: 100, original_total_amount: 100)
      payment = create(:payment, customer: paid_up, amount: 100, payment_method: 'cash')
      create(:payment_allocation, payment: payment, order: paid_order, amount: 100)
    end

    it 'includes customers with outstanding balance' do
      expect(Customer.with_outstanding_balance).to include(debtor)
    end

    it 'excludes customers with zero balance' do
      expect(Customer.with_outstanding_balance).not_to include(paid_up)
    end

    it 'excludes customers without credit account' do
      expect(Customer.with_outstanding_balance).not_to include(no_credit)
    end

    it 'excludes "Cliente Mostrador"' do
      Customer.mostrador # ensure the record exists in DB
      expect(Customer.with_outstanding_balance.map(&:name)).not_to include('Cliente Mostrador')
    end
  end

  describe "#current_balance — allocation-aware" do
    let(:customer) { create(:customer, :with_credit) }

    it "only counts payments allocated to credit orders" do
      create(:order, customer: customer, order_type: "credit", status: "confirmed", total_amount: 100)
      immediate_order = create(:order, customer: customer, order_type: "immediate", status: "confirmed", total_amount: 100)

      immediate_payment = create(:payment, customer: customer, amount: 100, payment_method: "cash")
      create(:payment_allocation, payment: immediate_payment, order: immediate_order, amount: 100)

      expect(customer.reload.current_balance).to eq(100)
    end

    it "is zero when the credit order is fully allocated" do
      credit_order = create(:order, customer: customer, order_type: "credit", status: "confirmed", total_amount: 100)
      credit_payment = create(:payment, customer: customer, amount: 100, payment_method: "cash")
      create(:payment_allocation, payment: credit_payment, order: credit_order, amount: 100)

      expect(customer.reload.current_balance).to eq(0)
    end
  end

  describe ".with_outstanding_balance — allocation-aware" do
    let(:customer) { create(:customer, :with_credit) }

    it "includes a customer with an unpaid credit order even if they have immediate-sale payments" do
      create(:order, customer: customer, order_type: "credit", status: "confirmed", total_amount: 100)
      immediate_order = create(:order, customer: customer, order_type: "immediate", status: "confirmed", total_amount: 200)

      immediate_payment = create(:payment, customer: customer, amount: 200, payment_method: "cash")
      create(:payment_allocation, payment: immediate_payment, order: immediate_order, amount: 200)

      expect(Customer.with_outstanding_balance).to include(customer)
    end

    it "excludes a customer whose only payments are for immediate orders if they have no credit orders" do
      immediate_order = create(:order, customer: customer, order_type: "immediate", status: "confirmed", total_amount: 100)
      immediate_payment = create(:payment, customer: customer, amount: 100, payment_method: "cash")
      create(:payment_allocation, payment: immediate_payment, order: immediate_order, amount: 100)

      expect(Customer.with_outstanding_balance).not_to include(customer)
    end

    it "excludes a customer whose credit orders are fully allocated" do
      credit_order = create(:order, customer: customer, order_type: "credit", status: "confirmed", total_amount: 100)
      credit_payment = create(:payment, customer: customer, amount: 100, payment_method: "cash")
      create(:payment_allocation, payment: credit_payment, order: credit_order, amount: 100)

      expect(Customer.with_outstanding_balance).not_to include(customer)
    end
  end

  describe "#current_balance — pending credit orders" do
    it "includes pending credit orders" do
      customer = create(:customer, :with_credit)
      create(:order, :credit_order, :pending,
             customer: customer, total_amount: 500, original_total_amount: 500)
      expect(customer.current_balance).to eq(500)
    end

    it "subtracts allocations on pending credit orders" do
      customer = create(:customer, :with_credit)
      order = create(:order, :credit_order, :pending,
                     customer: customer, total_amount: 500, original_total_amount: 500)
      payment = create(:payment, customer: customer, amount: 200)
      create(:payment_allocation, payment: payment, order: order, amount: 200)
      expect(customer.current_balance).to eq(300)
    end

    it "ignores immediate orders entirely" do
      customer = create(:customer, :with_credit)
      create(:order, :pending,
             customer: customer, order_type: "immediate",
             total_amount: 999, original_total_amount: 999)
      expect(customer.current_balance).to eq(0)
    end
  end

  describe ".with_outstanding_balance — pending credit orders" do
    it "includes customers with pending credit orders that have no allocations" do
      customer = create(:customer, :with_credit)
      create(:order, :credit_order, :pending,
             customer: customer, total_amount: 500, original_total_amount: 500)
      expect(described_class.with_outstanding_balance).to include(customer)
    end

    it "excludes customers whose credit orders are fully allocated" do
      customer = create(:customer, :with_credit)
      order = create(:order, :credit_order, :pending,
                     customer: customer, total_amount: 500, original_total_amount: 500)
      payment = create(:payment, customer: customer, amount: 500)
      create(:payment_allocation, payment: payment, order: order, amount: 500)
      # Note: this test does not invoke refresh_status_from_balance!; the order stays pending
      # but outstanding_balance == 0, so the SQL scope should still EXCLUDE this customer.
      expect(described_class.with_outstanding_balance).not_to include(customer)
    end
  end

  describe '#last_payment_date' do
    let(:customer) { create(:customer, :with_credit) }

    it 'returns nil when no payments exist' do
      expect(customer.last_payment_date).to be_nil
    end

    it 'returns the most recent payment date' do
      create(:payment, customer: customer, payment_date: 5.days.ago.to_date)
      create(:payment, customer: customer, payment_date: 2.days.ago.to_date)
      expect(customer.last_payment_date).to eq(2.days.ago.to_date)
    end
  end

  describe '#days_without_paying' do
    let(:customer) { create(:customer, :with_credit) }

    it 'returns nil when no payments exist' do
      expect(customer.days_without_paying).to be_nil
    end

    it 'returns 0 when last payment is today' do
      create(:payment, customer: customer, payment_date: Date.today)
      expect(customer.days_without_paying).to eq(0)
    end

    it 'returns number of days since last payment' do
      create(:payment, customer: customer, payment_date: 7.days.ago.to_date)
      expect(customer.days_without_paying).to eq(7)
    end
  end
end
