# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Web::Customers', type: :request do
  let!(:stock_location) { create(:stock_location) }
  let(:admin) { create(:user, role: 'admin') }
  let(:product) { create(:product, current_stock: 50, price_unit: 100) }

  before { sign_in admin }

  describe 'GET /web/customers/debtors' do
    let!(:debtor) { create(:customer, :with_credit) }
    let!(:paid_customer) { create(:customer, :with_credit) }
    let!(:no_credit_customer) { create(:customer, has_credit_account: false) }

    before do
      # debtor: unpaid order
      Sales::CreateOrder.call(
        customer: debtor,
        items: [ { product_id: product.id, quantity: 2, unit_price: 100 } ],
        order_type: 'credit',
        paper_number: 'L-0100'
      )

      # paid_customer: fully paid order — set up as credit order, then collect via AllocatePayment
      paid_order = Sales::CreateOrder.call(
        customer: paid_customer,
        items: [ { product_id: product.id, quantity: 1, unit_price: 100 } ],
        order_type: 'credit',
        paper_number: 'L-0101'
      ).record

      Payments::AllocatePayment.call(
        customer: paid_customer,
        payment_date: Date.current,
        allocations: [ { order_id: paid_order.id, amount: 100, payment_method: 'cash' } ]
      )
    end

    it 'returns 200' do
      get debtors_web_customers_path
      expect(response).to have_http_status(:ok)
    end

    it 'includes customers with outstanding balance' do
      get debtors_web_customers_path
      expect(response.body).to include(debtor.name)
    end

    it 'excludes customers with zero balance' do
      get debtors_web_customers_path
      expect(response.body).not_to include(paid_customer.name)
    end

    it 'excludes customers without credit account' do
      get debtors_web_customers_path
      expect(response.body).not_to include(no_credit_customer.name)
    end
  end
end
