require 'rails_helper'

RSpec.describe Customer, type: :model do
  describe 'associations' do
    it { should have_many(:orders).dependent(:nullify) }
    # Payment model doesn't exist yet, will be tested when implemented
    # it { should have_many(:payments).dependent(:destroy) }
  end

  describe 'validations' do
    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:customer_type) }
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
    let!(:workshop_customer) { create(:customer, :workshop) }
    let!(:mechanic_customer) { create(:customer, :mechanic) }
    let!(:store_customer) { create(:customer, :store) }
    let!(:credit_customer) { create(:customer, :with_credit, customer_type: 'retail') }

    describe '.with_credit_account' do
      it 'returns only customers with credit account' do
        expect(Customer.with_credit_account).to contain_exactly(workshop_customer, mechanic_customer, store_customer, credit_customer)
      end
    end

    describe '.retail' do
      it 'returns only retail customers' do
        expect(Customer.retail).to include(retail_customer, credit_customer)
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

      context 'with cash orders' do
        before do
          create(:order, customer: customer, order_type: 'cash', status: 'confirmed', total_amount: 1000)
        end

        it 'does not include cash orders in balance' do
          expect(customer.current_balance).to eq(0)
        end
      end
    end
  end
end
