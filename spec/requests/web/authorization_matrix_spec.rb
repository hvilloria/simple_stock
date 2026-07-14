# frozen_string_literal: true

require "rails_helper"

#
# Expected outcomes are derived from the policy classes in app/policies/, not from
# the documented intent. A policy unit spec proves the policy is right; only this
# request spec proves the controller actually calls it (a missing `authorize` fails
# open).
#
# Adding a route = adding one row to ROUTES.
module AuthMatrix
  # Set by ApplicationController#user_not_authorized.
  DENIED_FLASH = "No tenés permiso para realizar esta acción."

  ROLES = %w[vendedor caja admin].freeze
  ALL   = ROLES
  ADMIN = %w[admin].freeze

  # :path and :params are lambdas instance_exec'd inside the example, so they can
  # reach the `let` fixtures and the route helpers.
  ROUTES = [
    # --- Dashboard (DashboardPolicy) ---
    { name: "GET /web/dashboard", verb: :get, path: -> { web_dashboard_path }, allowed: ALL },

    # --- Products (ProductPolicy) ---
    { name: "GET /web/products", verb: :get, path: -> { web_products_path }, allowed: ALL },
    { name: "GET /web/products/search", verb: :get, path: -> { search_web_products_path }, allowed: ALL },
    { name: "GET /web/products/:id", verb: :get, path: -> { web_product_path(product) }, allowed: ALL },
    { name: "GET /web/products/new", verb: :get, path: -> { new_web_product_path }, allowed: %w[vendedor admin] },
    { name: "POST /web/products", verb: :post, path: -> { web_products_path },
      params: -> { { product: { sku: "SKU-MTX-1", name: "Producto matriz", category: "frenos", price_unit: "100", cost_unit: "50", cost_currency: "ARS", active: "1" } } },
      allowed: %w[vendedor admin] },
    { name: "GET /web/products/:id/edit", verb: :get, path: -> { edit_web_product_path(product) }, allowed: %w[vendedor admin] },
    { name: "PATCH /web/products/:id", verb: :patch, path: -> { web_product_path(product) },
      params: -> { { product: { name: "Nombre editado" } } },
      allowed: %w[vendedor admin] },
    { name: "DELETE /web/products/:id", verb: :delete, path: -> { web_product_path(product) }, allowed: ADMIN },
    { name: "GET /web/products/:product_id/stock_movements/new", verb: :get,
      path: -> { new_web_product_stock_movement_path(product) }, allowed: ADMIN },
    { name: "POST /web/products/:product_id/stock_movements", verb: :post,
      path: -> { web_product_stock_movements_path(product) },
      params: -> { { movement_type: "purchase", quantity: 5 } },
      allowed: ADMIN },

    # --- Orders (OrderPolicy) ---
    { name: "GET /web/orders", verb: :get, path: -> { web_orders_path }, allowed: ALL },
    { name: "GET /web/orders/:id", verb: :get, path: -> { web_order_path(pending_note) }, allowed: ALL },
    { name: "GET /web/orders/new", verb: :get, path: -> { new_web_order_path }, allowed: %w[vendedor admin] },
    { name: "POST /web/orders", verb: :post, path: -> { web_orders_path },
      params: lambda {
        {
          order: { customer_id: "mostrador", order_type: "immediate" },
          paper_number: "MTX-9001",
          source: "from_paper",
          purchase_items: [ { product_id: product.id, quantity: 1, unit_price: "150" } ]
        }
      },
      allowed: %w[vendedor admin] },
    # #cancel picks the policy method from the order state: cancel_pending? / cancel?
    { name: "POST /web/orders/:id/cancel (pending)", verb: :post, path: -> { cancel_web_order_path(pending_note) }, allowed: ALL },
    { name: "POST /web/orders/:id/cancel (confirmed)", verb: :post, path: -> { cancel_web_order_path(confirmed_order) }, allowed: ADMIN },

    # --- Sale notes (SaleNotePolicy) ---
    { name: "GET /web/sale_notes", verb: :get, path: -> { web_sale_notes_path }, allowed: %w[caja admin] },
    { name: "POST /web/sale_notes/:id/cancel", verb: :post, path: -> { cancel_web_sale_note_path(pending_note) }, allowed: ALL },
    { name: "GET /web/sale_notes/:sale_note_id/payment/new", verb: :get,
      path: -> { new_web_sale_note_payment_path(pending_note) }, allowed: %w[caja admin] },
    { name: "POST /web/sale_notes/:sale_note_id/payment", verb: :post,
      path: -> { web_sale_note_payment_path(pending_note) },
      params: -> { { discount_percent: 0, tenders: { "0" => { payment_method: "cash", amount: "100" } } } },
      allowed: %w[caja admin] },

    # --- Payments on account (PaymentOnAccountPolicy) ---
    { name: "GET /web/payments_on_account", verb: :get, path: -> { web_payments_on_account_index_path }, allowed: ALL },
    { name: "GET /web/payments_on_account/:id", verb: :get, path: -> { web_payments_on_account_path(on_account_order) }, allowed: ALL },
    { name: "POST /web/payments_on_account/:id/deliver", verb: :post,
      path: -> { deliver_web_payments_on_account_path(on_account_order) },
      params: -> { { order_item_ids: [ on_account_item.id ] } },
      allowed: %w[vendedor admin] },
    { name: "GET /web/payments_on_account/:id/payment/new", verb: :get,
      path: -> { new_web_payments_on_account_payment_path(on_account_order) }, allowed: %w[caja admin] },
    { name: "POST /web/payments_on_account/:id/payment", verb: :post,
      path: -> { web_payments_on_account_payment_path(on_account_order) },
      params: -> { { amount_to_settle: "100", payment_method: "cash", discount_percent: 0 } },
      allowed: %w[caja admin] },

    # --- Customers (CustomerPolicy) + nested payments (PaymentPolicy) ---
    { name: "GET /web/customers", verb: :get, path: -> { web_customers_path }, allowed: ALL },
    { name: "GET /web/customers/debtors", verb: :get, path: -> { debtors_web_customers_path }, allowed: ALL },
    { name: "GET /web/customers/:id", verb: :get, path: -> { web_customer_path(customer) }, allowed: ALL },
    { name: "GET /web/customers/new", verb: :get, path: -> { new_web_customer_path }, allowed: %w[vendedor admin] },
    { name: "POST /web/customers", verb: :post, path: -> { web_customers_path },
      params: -> { { customer: { name: "Cliente Matriz", document: "30111222", phone: "11 1111 1111", customer_type: "retail", has_credit_account: "0" } } },
      allowed: %w[vendedor admin] },
    { name: "GET /web/customers/:id/edit", verb: :get, path: -> { edit_web_customer_path(customer) }, allowed: ADMIN },
    { name: "PATCH /web/customers/:id", verb: :patch, path: -> { web_customer_path(customer) },
      params: -> { { customer: { phone: "11 2222 2222" } } },
      allowed: ADMIN },
    { name: "GET /web/customers/:customer_id/payments/new", verb: :get,
      path: -> { new_web_customer_payment_path(customer) }, allowed: %w[caja admin] },
    { name: "POST /web/customers/:customer_id/payments", verb: :post,
      path: -> { web_customer_payments_path(customer) },
      params: lambda {
        {
          payment_date: Date.current.to_s,
          allocations: { "0" => { order_id: credit_order.id, include: "1", amount: "100", payment_method: "cash" } }
        }
      },
      allowed: %w[caja admin] },

    # --- Suppliers (SupplierPolicy) ---
    { name: "GET /web/suppliers", verb: :get, path: -> { web_suppliers_path }, allowed: ADMIN },
    { name: "GET /web/suppliers/:id", verb: :get, path: -> { web_supplier_path(supplier) }, allowed: ADMIN },
    { name: "GET /web/suppliers/new", verb: :get, path: -> { new_web_supplier_path }, allowed: ADMIN },
    { name: "POST /web/suppliers", verb: :post, path: -> { web_suppliers_path },
      params: -> { { supplier: { name: "Proveedor Matriz" } } },
      allowed: ADMIN },
    { name: "GET /web/suppliers/:id/edit", verb: :get, path: -> { edit_web_supplier_path(supplier) }, allowed: ADMIN },
    { name: "PATCH /web/suppliers/:id", verb: :patch, path: -> { web_supplier_path(supplier) },
      params: -> { { supplier: { phone: "11 3333 3333" } } },
      allowed: ADMIN },
    # SupplierPolicy#destroy? also requires the supplier to have no invoices; this
    # `supplier` is lazily created without any.
    { name: "DELETE /web/suppliers/:id", verb: :delete, path: -> { web_supplier_path(supplier) }, allowed: ADMIN },

    # --- Invoices (InvoicePolicy) ---
    { name: "GET /web/invoices", verb: :get, path: -> { web_invoices_path }, allowed: ADMIN },
    # InvoicePolicy#view_pending? is `user.present?` — open to every role.
    { name: "GET /web/invoices/pending", verb: :get, path: -> { pending_web_invoices_path }, allowed: ALL },
    { name: "GET /web/invoices/:id", verb: :get, path: -> { web_invoice_path(invoice) }, allowed: ADMIN },
    { name: "GET /web/invoices/new", verb: :get, path: -> { new_web_invoice_path }, allowed: ADMIN },
    { name: "POST /web/invoices", verb: :post, path: -> { web_invoices_path },
      params: lambda {
        {
          supplier_id: supplier.id, invoice_number: "F-MTX-1", amount: "1000", currency: "ARS",
          purchase_date: Date.current.to_s, due_date: 30.days.from_now.to_date.to_s
        }
      },
      allowed: ADMIN },
    { name: "GET /web/invoices/:id/edit", verb: :get, path: -> { edit_web_invoice_path(invoice) }, allowed: ADMIN },
    { name: "PATCH /web/invoices/:id", verb: :patch, path: -> { web_invoice_path(invoice) },
      params: -> { { invoice: { notes: "Nota editada" } } },
      allowed: ADMIN },
    { name: "POST /web/invoices/:id/mark_as_paid", verb: :post, path: -> { mark_as_paid_web_invoice_path(invoice) }, allowed: ADMIN },
    { name: "PATCH /web/invoices/:id/cancel", verb: :patch, path: -> { cancel_web_invoice_path(invoice) }, allowed: ADMIN },
    { name: "POST /web/invoices/mark_supplier_paid", verb: :post, path: -> { mark_supplier_paid_web_invoices_path },
      params: -> { { invoice_ids: [ invoice.id ], period: "this_week" } },
      allowed: ADMIN },

    # --- Credit notes (CreditNotePolicy) ---
    # Everything except destroy is `user.present?` — open to every role.
    { name: "GET /web/credit_notes", verb: :get, path: -> { web_credit_notes_path }, allowed: ALL },
    { name: "GET /web/credit_notes/supplier_invoices", verb: :get,
      path: -> { supplier_invoices_web_credit_notes_path },
      params: -> { { supplier_id: supplier.id } },
      allowed: ALL },
    { name: "GET /web/credit_notes/:id", verb: :get, path: -> { web_credit_note_path(credit_note) }, allowed: ALL },
    { name: "GET /web/credit_notes/new", verb: :get, path: -> { new_web_credit_note_path }, allowed: ALL },
    { name: "POST /web/credit_notes", verb: :post, path: -> { web_credit_notes_path },
      params: lambda {
        {
          credit_note: {
            supplier_id: supplier.id, credit_note_number: "NC-MTX-1", amount: "1000",
            currency: "ARS", issue_date: Date.current.to_s
          }
        }
      },
      allowed: ALL },
    { name: "GET /web/credit_notes/:id/edit", verb: :get, path: -> { edit_web_credit_note_path(credit_note) }, allowed: ALL },
    { name: "PATCH /web/credit_notes/:id", verb: :patch, path: -> { web_credit_note_path(credit_note) },
      params: -> { { credit_note: { notes: "Nota editada" } } },
      allowed: ALL },
    { name: "DELETE /web/credit_notes/:id", verb: :delete, path: -> { web_credit_note_path(credit_note) }, allowed: ADMIN }
  ].freeze
end

RSpec.describe "Web authorization matrix", type: :request do
  # StockLocation.first! runs in a before_action ahead of `authorize`, so it must
  # exist or the stock_movements rows would 404 instead of denying.
  let!(:stock_location) { create(:stock_location) }

  let(:product)  { create(:product) }
  let(:supplier) { create(:supplier) }
  let(:invoice)  { create(:invoice, :simple_mode, supplier: supplier) }

  let(:credit_note) { create(:credit_note, supplier: supplier) }

  let(:customer) { create(:customer, :with_credit) }
  let(:credit_order) do
    create(:order, :pending, order_type: "credit", customer: customer,
                             total_amount: 100, original_total_amount: 100)
  end

  let(:pending_note) do
    order = create(:order, :pending, order_type: "immediate", total_amount: 100, original_total_amount: 100)
    create(:order_item, order: order, product: product, quantity: 1, unit_price: 100)
    order
  end

  let(:confirmed_order) { create(:order, order_type: "immediate", total_amount: 100, original_total_amount: 100) }

  let(:on_account_order) do
    create(:order, :on_account, total_amount: 100, original_total_amount: 100)
  end
  let(:on_account_item) do
    create(:order_item, order: on_account_order, product: product, quantity: 1, unit_price: 100)
  end

  AuthMatrix::ROUTES.each do |route|
    describe route[:name] do
      AuthMatrix::ROLES.each do |role|
        allowed = route[:allowed].include?(role)

        it "#{allowed ? 'allows' : 'denies'} #{role}" do
          sign_in create(:user, role: role)

          path   = instance_exec(&route[:path])
          params = route[:params] ? instance_exec(&route[:params]) : {}

          public_send(route[:verb], path, params: params)

          if allowed
            expect(flash[:alert]).not_to eq(AuthMatrix::DENIED_FLASH)
            expect(response.status).to be < 400
          else
            expect(response).to have_http_status(:redirect)
            expect(flash[:alert]).to eq(AuthMatrix::DENIED_FLASH)
          end
        end
      end
    end
  end
end
