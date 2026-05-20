# Payment Method on All Sales — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record the payment method (cash, transfer, check, card) for every sale — not just credit ones — by extending `Sales::CreateOrder` to accept a `payments:` array, making `Customer#current_balance` allocation-aware, and replacing the single-method UI with a multi-row payment block.

**Architecture:** Behavioral-only change (no migrations). The existing `Payment` + `PaymentAllocation` tables already support what's needed. Immediate orders will require `payments` summing to total; credit orders accept optional payments summing ≤ total. `Customer#current_balance` switches from `payments.sum` to allocation-based formula so immediate-sale payments don't offset credit debt.

**Tech Stack:** Rails 7.2, RSpec, HAML, Stimulus, TailwindCSS, PostgreSQL

**Spec:** `docs/superpowers/specs/2026-05-18-payment-method-on-all-sales-design.md`

**Branch:** `feat_07-payment-method-on-all-sales` (created from `main`, already current).

**Commit strategy:** ONE single commit at the very end (Task 12). No intermediate commits.

---

## File Structure

**Models (behavioral):**
- `app/models/payment.rb` — drop `customer_must_have_credit_account`
- `app/models/customer.rb` — `current_balance` and `with_outstanding_balance` use `payment_allocations`

**Service:**
- `app/services/sales/create_order.rb` — drop `initial_payment:` kwarg; add `payments:` array with per-type validation; replace `create_initial_payment` with `create_payments`

**Controller + UI:**
- `app/controllers/web/orders_controller.rb` — `parse_payments` replaces `parse_initial_payment`
- `app/views/web/orders/new.html.haml` — multi-row payment block visible for both order types
- `app/javascript/controllers/order_form_controller.js` — extend with multi-row dynamics + submit guard

**Tests (all updated to new contract):**
- `spec/models/payment_spec.rb`, `spec/models/customer_spec.rb`, `spec/models/order_spec.rb`, `spec/models/payment_allocation_spec.rb`
- `spec/services/sales/create_order_spec.rb`, `spec/services/sales/cancel_order_spec.rb`, `spec/services/payments/allocate_payment_spec.rb`
- `spec/requests/web/orders_spec.rb`, `spec/requests/web/customers_spec.rb`, `spec/requests/web/customers/payments_spec.rb`

**Seeds:**
- `db/seeds.rb` — immediate sales now pass `payments:` array

**Docs:**
- `WORKING_CONTEXT.md` — update payment-flow section

---

## Task 1: Baseline verification

**Files:**
- None (verification only)

- [ ] **Step 1: Confirm branch and clean state**

```bash
git status
git branch --show-current
```

Expected: branch `feat_07-payment-method-on-all-sales`, working tree clean except untracked `docs/pendientes.txt` and the spec/plan files in `docs/superpowers/`.

- [ ] **Step 2: Run baseline test suite**

```bash
fish -l -c 'bundle exec rspec'
```

Expected: ~870+ examples, 0 failures except up to 5 known pre-existing date-drift failures in `customer_spec.rb` and `invoice_spec.rb`. Record baseline counts so Task 12 can compare.

- [ ] **Step 3: Run baseline rubocop**

```bash
fish -l -c 'bundle exec rubocop'
```

Expected: 0 offenses.

---

## Task 2: Drop `customer_must_have_credit_account` from `Payment`

**Files:**
- Modify: `app/models/payment.rb:16` (remove `validate :customer_must_have_credit_account`) and lines 22-30 (remove the private method)
- Test: `spec/models/payment_spec.rb` (existing examples that assert the validation must be removed; add positive examples for retail customers)

- [ ] **Step 1: Read current `payment_spec.rb` and locate the credit-account validation examples**

```bash
grep -n "credit account" /home/hoswardv/Projects/simple_stock/spec/models/payment_spec.rb
```

- [ ] **Step 2: Replace those examples with positive ones**

Remove any example like `"is invalid when customer has no credit account"`.

Add:

```ruby
context "for a customer without a credit account (retail / mostrador)" do
  let(:retail) { create(:customer, customer_type: "retail", has_credit_account: false) }

  it "is valid" do
    payment = Payment.new(
      customer: retail,
      amount: 100,
      payment_method: "cash",
      payment_date: Date.today
    )
    expect(payment).to be_valid
  end
end
```

- [ ] **Step 3: Run the new spec and confirm it fails**

```bash
fish -l -c 'bundle exec rspec spec/models/payment_spec.rb -e "for a customer without a credit account"'
```

Expected: FAIL with "Customer must have credit account enabled".

- [ ] **Step 4: Remove the validation from `Payment`**

In `app/models/payment.rb`:

```ruby
# frozen_string_literal: true

class Payment < ApplicationRecord
  # Associations
  belongs_to :customer
  has_many :allocations, class_name: "PaymentAllocation", dependent: :destroy
  has_many :orders, through: :allocations

  # Constants
  PAYMENT_METHODS = %w[cash transfer check card].freeze

  # Validations
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :payment_method, presence: true, inclusion: { in: PAYMENT_METHODS }
  validates :payment_date, presence: true

  # Scopes
  scope :by_customer, ->(customer) { where(customer: customer) }
  scope :recent, -> { order(payment_date: :desc, created_at: :desc) }
end
```

(Removes `validate :customer_must_have_credit_account` and the private method that implemented it.)

- [ ] **Step 5: Re-run the payment spec — all examples pass**

```bash
fish -l -c 'bundle exec rspec spec/models/payment_spec.rb'
```

Expected: 0 failures.

---

## Task 3: `Customer#current_balance` uses allocation-based formula

**Files:**
- Modify: `app/models/customer.rb:50-61` (the `current_balance` method)
- Test: `spec/models/customer_spec.rb` (add new examples)

- [ ] **Step 1: Add failing tests for allocation-based balance**

Append to `spec/models/customer_spec.rb` (inside the existing `describe "#current_balance"` block, or add the block if missing):

```ruby
describe "#current_balance — allocation-aware" do
  let!(:stock_location) { create(:stock_location) }
  let(:customer) { create(:customer, :with_credit) }
  let(:product) do
    p = create(:product, price_unit: 100)
    create(:stock_movement, product: p, stock_location: stock_location, movement_type: "purchase", quantity: 100)
    p.recalculate_current_stock!
    p
  end

  it "only counts payments allocated to credit orders" do
    credit_order = Sales::CreateOrder.call(
      customer: customer, order_type: "credit",
      items: [{ product_id: product.id, quantity: 1, unit_price: 100 }],
      payments: []
    ).record

    Sales::CreateOrder.call(
      customer: customer, order_type: "immediate",
      items: [{ product_id: product.id, quantity: 1, unit_price: 100 }],
      payments: [{ amount: 100, payment_method: "cash" }]
    )

    expect(customer.reload.current_balance).to eq(100)
  end

  it "is zero when the credit order is fully allocated" do
    Sales::CreateOrder.call(
      customer: customer, order_type: "credit",
      items: [{ product_id: product.id, quantity: 1, unit_price: 100 }],
      payments: [{ amount: 100, payment_method: "cash" }]
    )

    expect(customer.reload.current_balance).to eq(0)
  end
end
```

- [ ] **Step 2: Run new examples and confirm they fail**

```bash
fish -l -c 'bundle exec rspec spec/models/customer_spec.rb -e "allocation-aware"'
```

Expected: FAIL — `payments:` keyword not yet accepted by `Sales::CreateOrder` (this will be addressed in Task 5); skip for now and verify the formula update by writing a more isolated test that creates Payment + PaymentAllocation manually:

Replace the examples above with manual-setup versions:

```ruby
describe "#current_balance — allocation-aware" do
  let!(:stock_location) { create(:stock_location) }
  let(:customer) { create(:customer, :with_credit) }
  let(:product) do
    p = create(:product, price_unit: 100)
    create(:stock_movement, product: p, stock_location: stock_location, movement_type: "purchase", quantity: 100)
    p.recalculate_current_stock!
    p
  end

  it "only counts payments allocated to credit orders" do
    credit_order = create(:order, customer: customer, order_type: "credit", status: "confirmed", total_amount: 100)
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
```

```bash
fish -l -c 'bundle exec rspec spec/models/customer_spec.rb -e "allocation-aware"'
```

Expected: FAIL (first example) — current formula deducts ALL payments, so balance is 0 instead of 100.

- [ ] **Step 3: Update `Customer#current_balance`**

Replace lines 49-61 of `app/models/customer.rb`:

```ruby
# Calculate current balance for customers with credit account.
# Only payments allocated to credit orders count against the balance —
# payments for immediate sales do not.
def current_balance
  return 0 unless has_credit_account?

  credit_owed = orders
                  .where(order_type: "credit", status: "confirmed")
                  .sum(:total_amount)

  credit_paid = PaymentAllocation
                  .joins(:order)
                  .where(orders: { customer_id: id, order_type: "credit", status: "confirmed" })
                  .sum(:amount)

  credit_owed - credit_paid
end
```

- [ ] **Step 4: Run the customer spec**

```bash
fish -l -c 'bundle exec rspec spec/models/customer_spec.rb'
```

Expected: new allocation-aware examples pass. Pre-existing date-drift failures may persist (they're unrelated). Other customer_spec examples MUST still pass.

---

## Task 4: `Customer.with_outstanding_balance` allocation-based

**Files:**
- Modify: `app/models/customer.rb:25-38` (the `with_outstanding_balance` scope)
- Test: `spec/models/customer_spec.rb`

- [ ] **Step 1: Add failing test**

```ruby
describe ".with_outstanding_balance — allocation-aware" do
  let!(:stock_location) { create(:stock_location) }
  let(:customer) { create(:customer, :with_credit) }
  let(:product) do
    p = create(:product, price_unit: 100)
    create(:stock_movement, product: p, stock_location: stock_location, movement_type: "purchase", quantity: 100)
    p.recalculate_current_stock!
    p
  end

  it "includes a customer with an unpaid credit order even if they have immediate-sale payments" do
    credit_order = create(:order, customer: customer, order_type: "credit", status: "confirmed", total_amount: 100)
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
end
```

```bash
fish -l -c 'bundle exec rspec spec/models/customer_spec.rb -e "with_outstanding_balance — allocation-aware"'
```

Expected: first example FAILS — current scope counts the immediate payment against credit, so a $100 credit + $200 immediate payment misleadingly shows balance < 0 → excluded.

- [ ] **Step 2: Update the scope**

Replace lines 25-38 of `app/models/customer.rb`:

```ruby
scope :with_outstanding_balance, -> {
  with_credit_account.where(
    "( SELECT COALESCE(SUM(o.total_amount), 0)
       FROM orders o
       WHERE o.customer_id = customers.id
         AND o.order_type = 'credit'
         AND o.status = 'confirmed' )
     >
     ( SELECT COALESCE(SUM(pa.amount), 0)
       FROM payment_allocations pa
       JOIN orders o ON pa.order_id = o.id
       WHERE o.customer_id = customers.id
         AND o.order_type = 'credit'
         AND o.status = 'confirmed' )"
  )
}
```

- [ ] **Step 3: Run customer_spec**

```bash
fish -l -c 'bundle exec rspec spec/models/customer_spec.rb'
```

Expected: new examples pass.

---

## Task 5: `Sales::CreateOrder` — `payments:` array replaces `initial_payment:`

This is the largest task. It updates the service signature **and** every existing caller and spec in one atomic move so the suite stays green at the task boundary.

**Files:**
- Modify: `app/services/sales/create_order.rb` (full refactor — see Step 3)
- Modify: `app/controllers/web/orders_controller.rb:57-66, 122-133` (rename kwarg + helper — Task 6 handles the controller in more depth; here we just keep it compiling)
- Modify: `db/seeds.rb:328, 368` (the two `Sales::CreateOrder.call` invocations)
- Modify (specs): `spec/services/sales/create_order_spec.rb`, `spec/services/sales/cancel_order_spec.rb`, `spec/services/payments/allocate_payment_spec.rb`, `spec/models/customer_spec.rb`, `spec/models/order_spec.rb`, `spec/models/payment_allocation_spec.rb`, `spec/requests/web/customers_spec.rb`, `spec/requests/web/customers/payments_spec.rb`, `spec/requests/web/orders_spec.rb`

- [ ] **Step 1: Add the new behavior to `create_order_spec.rb`**

Open `spec/services/sales/create_order_spec.rb` and add a `describe "#payments handling"` block. Replace any existing examples that use `initial_payment:` with the new `payments:` array contract:

```ruby
describe "#payments handling" do
  let!(:stock_location) { create(:stock_location) }
  let(:credit_customer) { create(:customer, :with_credit) }
  let(:retail_customer) { create(:customer, customer_type: "retail", has_credit_account: false, name: "Mostrador") }
  let(:product) do
    p = create(:product, price_unit: 100)
    create(:stock_movement, product: p, stock_location: stock_location, movement_type: "purchase", quantity: 100)
    p.recalculate_current_stock!
    p
  end

  context "immediate order" do
    it "fails when payments are empty" do
      result = Sales::CreateOrder.call(
        customer: retail_customer, order_type: "immediate",
        items: [{ product_id: product.id, quantity: 1, unit_price: 100 }],
        payments: []
      )
      expect(result.failure?).to be true
      expect(result.errors.join).to match(/pago.*requerido|payment.*required/i)
    end

    it "fails when payments do not sum to total" do
      result = Sales::CreateOrder.call(
        customer: retail_customer, order_type: "immediate",
        items: [{ product_id: product.id, quantity: 1, unit_price: 100 }],
        payments: [{ amount: 50, payment_method: "cash" }]
      )
      expect(result.failure?).to be true
      expect(result.errors.join).to match(/suma.*total|sum.*total/i)
    end

    it "creates one Payment + one PaymentAllocation when a single payment matches total" do
      expect {
        result = Sales::CreateOrder.call(
          customer: retail_customer, order_type: "immediate",
          items: [{ product_id: product.id, quantity: 1, unit_price: 100 }],
          payments: [{ amount: 100, payment_method: "cash" }]
        )
        expect(result.success?).to be true
      }.to change(Payment, :count).by(1).and change(PaymentAllocation, :count).by(1)
    end

    it "creates two Payments + two Allocations when split across methods" do
      expect {
        result = Sales::CreateOrder.call(
          customer: retail_customer, order_type: "immediate",
          items: [{ product_id: product.id, quantity: 2, unit_price: 100 }],
          payments: [
            { amount: 80, payment_method: "cash" },
            { amount: 120, payment_method: "transfer" }
          ]
        )
        expect(result.success?).to be true
      }.to change(Payment, :count).by(2).and change(PaymentAllocation, :count).by(2)
    end
  end

  context "credit order" do
    it "succeeds with empty payments" do
      expect {
        result = Sales::CreateOrder.call(
          customer: credit_customer, order_type: "credit",
          items: [{ product_id: product.id, quantity: 1, unit_price: 100 }],
          payments: []
        )
        expect(result.success?).to be true
      }.to change(Payment, :count).by(0)
    end

    it "succeeds with a partial upfront payment" do
      expect {
        result = Sales::CreateOrder.call(
          customer: credit_customer, order_type: "credit",
          items: [{ product_id: product.id, quantity: 1, unit_price: 100 }],
          payments: [{ amount: 60, payment_method: "transfer" }]
        )
        expect(result.success?).to be true
      }.to change(Payment, :count).by(1).and change(PaymentAllocation, :count).by(1)
    end

    it "fails when payments exceed the total" do
      result = Sales::CreateOrder.call(
        customer: credit_customer, order_type: "credit",
        items: [{ product_id: product.id, quantity: 1, unit_price: 100 }],
        payments: [{ amount: 150, payment_method: "cash" }]
      )
      expect(result.failure?).to be true
      expect(result.errors.join).to match(/total|exceed/i)
    end
  end
end
```

Also REMOVE any existing examples in `create_order_spec.rb` that pass `initial_payment:` (they're superseded by the block above).

- [ ] **Step 2: Run new examples — confirm they fail**

```bash
fish -l -c 'bundle exec rspec spec/services/sales/create_order_spec.rb -e "payments handling"'
```

Expected: FAIL — `payments:` keyword unknown.

- [ ] **Step 3: Update `app/services/sales/create_order.rb`**

Full replacement file:

```ruby
module Sales
  # Sales::CreateOrder
  #
  # Crea órdenes de venta + pagos asociados en una sola transacción.
  #
  # Modos:
  #   - LIVE (default): precios desde la BD, valida stock disponible
  #   - FROM_PAPER:     unit_price puede ser nil, total puede ser 0,
  #                     requiere paper_number, no valida stock
  #
  # Pagos (`payments:` array de `{ amount:, payment_method: }`):
  #   - immediate: OBLIGATORIO, sum(amount) == total_amount (tolerancia 0.01)
  #   - credit:    OPCIONAL, sum(amount) <= total_amount
  #
  # Cada entrada produce un `Payment` + `PaymentAllocation` apuntando a la
  # orden recién creada.
  class CreateOrder
    Item = Struct.new(:product_id, :quantity, :unit_price, keyword_init: true)
    PAYMENT_SUM_TOLERANCE = 0.01

    def self.call(customer:, items:, order_type:, channel: nil, source: "live",
                  sale_date: nil, paper_number: nil, payments: [])
      new(
        customer: customer,
        items: items,
        order_type: order_type,
        channel: channel,
        source: source,
        sale_date: sale_date,
        paper_number: paper_number,
        payments: payments
      ).call
    end

    def initialize(customer:, items:, order_type:, channel: nil, source: "live",
                   sale_date: nil, paper_number: nil, payments: [])
      @customer = customer
      @items = items.map { |item| item.is_a?(Item) ? item : Item.new(item) }
      @order_type = order_type
      @channel = channel
      @source = source
      @sale_date = sale_date || Date.today
      @paper_number = paper_number
      @payments_data = normalize_payments(payments)
    end

    def call
      validate_params

      ActiveRecord::Base.transaction do
        create_order
        create_order_items
        create_payments if @payments_data.any?

        Result.new(success?: true, record: @order, errors: [])
      end
    rescue ValidationError => e
      Result.new(success?: false, record: nil, errors: [ e.message ])
    rescue StandardError => e
      Rails.logger.error("Error in Sales::CreateOrder: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      Result.new(success?: false, record: nil, errors: [ "Error creating order" ])
    end

    private

    class ValidationError < StandardError; end

    def normalize_payments(payments)
      Array(payments).filter_map do |entry|
        h = entry.to_h.symbolize_keys
        amount = h[:amount].to_f
        next if amount <= 0
        { amount: amount, payment_method: h[:payment_method] }
      end
    end

    def validate_params
      unless %w[immediate credit].include?(@order_type)
        raise ValidationError, "Invalid order type"
      end

      raise ValidationError, "Customer is required" if @customer.nil?

      if @order_type == "credit" && !@customer.has_credit_account?
        raise ValidationError, "Customer does not have credit account enabled"
      end

      raise ValidationError, "At least one product is required" if @items.blank?

      @items.each do |item|
        raise ValidationError, "Product ID is required" unless item.product_id
        raise ValidationError, "Quantity must be greater than zero" unless item.quantity.to_i > 0
      end

      unless @source == "from_paper"
        @items.each do |item|
          product = Product.find(item.product_id)
          if product.current_stock < item.quantity
            raise ValidationError, "Insufficient stock for #{product.name}. Available: #{product.current_stock}"
          end
        end
      end

      validate_payments
    end

    def validate_payments
      @payments_data.each do |entry|
        unless Payment::PAYMENT_METHODS.include?(entry[:payment_method])
          raise ValidationError, "Método de pago inválido: #{entry[:payment_method]}"
        end
      end

      total = calculate_total
      paid_sum = @payments_data.sum { |e| e[:amount] }

      case @order_type
      when "immediate"
        if @payments_data.empty?
          raise ValidationError, "El pago es requerido para ventas de contado"
        end
        if (paid_sum - total).abs > PAYMENT_SUM_TOLERANCE
          raise ValidationError, "La suma de los pagos ($#{paid_sum}) debe coincidir con el total de la venta ($#{total})"
        end
      when "credit"
        if paid_sum > total + PAYMENT_SUM_TOLERANCE
          raise ValidationError, "El monto cobrado no puede exceder el total de la venta ($#{total})"
        end
      end
    end

    def create_order
      @order = Order.create!(
        customer: @customer,
        order_type: @order_type,
        channel: @channel,
        source: @source,
        sale_date: @sale_date,
        paper_number: @paper_number,
        status: "confirmed",
        total_amount: calculate_total
      )
    end

    def calculate_total
      @items.sum do |item|
        product = Product.find(item.product_id)
        unit_price = item.unit_price || product.price_unit || 0
        item.quantity * unit_price
      end
    end

    def create_order_items
      @items.each do |item|
        product = Product.find(item.product_id)
        final_price = item.unit_price || product.price_unit || 0

        OrderItem.create!(
          order: @order,
          product: product,
          quantity: item.quantity,
          unit_price: final_price
        )
      end
    end

    def create_payments
      @payments_data.each do |entry|
        payment = Payment.create!(
          customer:       @customer,
          amount:         entry[:amount],
          payment_method: entry[:payment_method],
          payment_date:   @sale_date
        )
        PaymentAllocation.create!(
          payment: payment,
          order:   @order,
          amount:  entry[:amount]
        )
      end
    end
  end
end
```

- [ ] **Step 4: Update every existing spec call site away from `initial_payment:`**

Find usages:

```bash
grep -rn "initial_payment" /home/hoswardv/Projects/simple_stock/spec /home/hoswardv/Projects/simple_stock/app
```

Updates required (verbatim — apply each):

**`spec/models/customer_spec.rb:225`** — change `initial_payment: { amount: 100, payment_method: 'cash' }` → `payments: [{ amount: 100, payment_method: "cash" }]`

**`spec/models/order_spec.rb:277`** — `initial_payment: { amount: 50, payment_method: "cash" }` → `payments: [{ amount: 50, payment_method: "cash" }]`

**`spec/models/order_spec.rb:292`** — `initial_payment: { amount: 200, payment_method: "cash" }` → `payments: [{ amount: 200, payment_method: "cash" }]`. NOTE: if the test was asserting that `200 > total` fails for credit, leave the expectation (it should still fail because `200 > total`).

**`spec/requests/web/customers_spec.rb:30`** — `initial_payment: { amount: 100, payment_method: 'cash' }` → `payments: [{ amount: 100, payment_method: "cash" }]`

- [ ] **Step 5: Update every spec that creates an `immediate` order via `Sales::CreateOrder` without payments**

Every `immediate` order call must now include a matching `payments:` array. Affected files (verify each `Sales::CreateOrder.call` whose `order_type:` is `"immediate"` or default):

- `spec/services/sales/cancel_order_spec.rb` (lines 15, 79, 97, 112, 130, 164, 203, 226 — check each)
- `spec/services/payments/allocate_payment_spec.rb` (lines 16, 24, 56, 72)
- `spec/models/payment_allocation_spec.rb` (lines 23, 38, 55)
- `spec/models/order_spec.rb` (lines 230, 244, 259, 273, 288)
- `spec/models/customer_spec.rb` (lines 214, 221)
- `spec/requests/web/customers/payments_spec.rb` (lines 21, 57, 65)
- `spec/requests/web/customers_spec.rb` (lines 19, 26)

For each, locate the `Sales::CreateOrder.call(...)` block. If `order_type:` is `"immediate"`:
- Calculate the expected total from items
- Add `payments: [{ amount: <total>, payment_method: "cash" }]`

Example mechanical transform:

Before:
```ruby
Sales::CreateOrder.call(
  customer: customer,
  order_type: "immediate",
  items: [{ product_id: product.id, quantity: 2, unit_price: 50 }]
)
```

After:
```ruby
Sales::CreateOrder.call(
  customer: customer,
  order_type: "immediate",
  items: [{ product_id: product.id, quantity: 2, unit_price: 50 }],
  payments: [{ amount: 100, payment_method: "cash" }]
)
```

If `order_type:` is `"credit"` and there is no `initial_payment:`, leave it alone (credit orders default to no payment, which is still valid).

- [ ] **Step 6: Update `db/seeds.rb`**

Both `Sales::CreateOrder.call` invocations need updating.

Lines around 328 (immediate sales — mostrador). Compute total from items first, then pass it:

```ruby
total = items.sum { |i| i[:quantity] * i[:unit_price] }

result = Sales::CreateOrder.call(
  customer: mostrador,
  items: items,
  order_type: "immediate",
  channel: [ 'counter', 'whatsapp', 'mercadolibre' ].sample,
  payments: [{ amount: total, payment_method: %w[cash transfer card].sample }]
)
```

Lines around 368 (credit sales — talleres). Add an optional partial payment for variety:

```ruby
total = items.sum { |i| i[:quantity] * i[:unit_price] }
partial = (total * rand(0..0.5)).round(2)
payments = partial.positive? ? [{ amount: partial, payment_method: %w[cash transfer].sample }] : []

result = Sales::CreateOrder.call(
  customer: cliente,
  items: items,
  order_type: "credit",
  channel: "counter",
  payments: payments
)
```

- [ ] **Step 7: Update `app/controllers/web/orders_controller.rb` to a temporary shim**

Task 6 will properly refactor this. For now, keep it compiling by renaming the kwarg:

Replace lines 57-66:

```ruby
result = Sales::CreateOrder.call(
  customer: find_or_create_customer,
  items: parse_items,
  order_type: params.dig(:order, :order_type) || "immediate",
  channel: params.dig(:order, :channel),
  source: params[:source] || "live",
  sale_date: params[:sale_date],
  paper_number: params[:paper_number],
  payments: parse_payments
)
```

Replace `parse_initial_payment` (lines 122-133) with a temporary `parse_payments` that reads BOTH the old and new param shapes (this keeps the existing form working until Task 7-8 update it):

```ruby
def parse_payments
  # New shape: params[:payments] = { "0" => { amount:, payment_method: } }
  if params[:payments].present?
    return params[:payments].to_unsafe_h.values.filter_map do |entry|
      amount = entry[:amount].to_f
      next if amount <= 0
      { amount: amount, payment_method: entry[:payment_method].presence || "cash" }
    end
  end

  # Old shape (still used by the un-updated view): params[:initial_payment_amount]
  return [] if params[:initial_payment_amount].blank?
  amount = params[:initial_payment_amount].to_f
  return [] if amount <= 0

  [{ amount: amount, payment_method: params[:initial_payment_method].presence || "cash" }]
end
```

- [ ] **Step 8: Run the entire suite**

```bash
fish -l -c 'bundle exec rspec'
```

Expected: 0 new failures. Pre-existing date-drift failures may remain.

If anything fails, fix the offending spec/seeds entry by following Steps 4-6 mechanically.

---

## Task 6: Refactor `Web::OrdersController` cleanly

This task removes the temporary shim from Task 5 Step 7 once the view (Task 7) is updated. We'll order: update view (Task 7), update Stimulus (Task 8), then return here in Task 9 to drop the legacy fallback. So Task 6 is mostly a placeholder — verify the controller currently calls `Sales::CreateOrder` with `payments:` and that `parse_payments` exists.

**Files:**
- Verify: `app/controllers/web/orders_controller.rb`

- [ ] **Step 1: Verify the kwarg + helper rename**

```bash
grep -n "parse_payments\|payments:" /home/hoswardv/Projects/simple_stock/app/controllers/web/orders_controller.rb
```

Expected: both names present. No further changes here yet — proceed to Task 7.

---

## Task 7: Replace the credit-only payment block in `new.html.haml` with a multi-row block

**Files:**
- Modify: `app/views/web/orders/new.html.haml` — replace lines 80-97 (the `creditPaymentSection` block)

- [ ] **Step 1: Replace the block**

Locate the `-# Cobro al momento (visible solo en cuenta corriente)` block (lines ~80-97) and replace it entirely with:

```haml
          -# Detalle de pago (visible para ambos tipos de venta)
          .border-t.border-gray-200.pt-4{ data: { order_form_target: "paymentSection" } }
            .flex.items-center.justify-between.mb-3
              %div
                %h4.text-sm.font-semibold.text-gray-900{ data: { order_form_target: "paymentSectionTitle" } }
                  Detalle de Pago
                %p.text-xs.text-gray-500.mt-0.5{ data: { order_form_target: "paymentSectionSubtitle" } }
                  La suma debe coincidir con el total de la venta
              %span.text-xs.font-semibold.px-2.py-0.5.rounded.bg-red-50.text-red-700{ data: { order_form_target: "paymentSectionBadge" } }
                Requerido

            .space-y-2.mb-3{ data: { order_form_target: "paymentRows" } }
              .flex.gap-2.items-center{ data: { order_form_target: "paymentRow" } }
                = select_tag "payments[0][payment_method]",
                    options_for_select([["💵 Efectivo", "cash"], ["🏦 Transferencia", "transfer"], ["📄 Cheque", "check"], ["💳 Tarjeta", "card"]], "cash"),
                    data: { order_form_target: "paymentMethod" },
                    class: "flex-1 px-3 py-2 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-gray-700 focus:border-transparent"
                = number_field_tag "payments[0][amount]", nil,
                    step: "0.01", min: "0", placeholder: "Monto",
                    data: { order_form_target: "paymentAmount", action: "input->order-form#updatePaymentTotal" },
                    class: "w-32 px-3 py-2 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-gray-700 focus:border-transparent"
                %button{ type: "button", data: { action: "click->order-form#removePaymentRow" }, class: "text-gray-400 hover:text-red-500 text-lg px-1", aria: { label: "Quitar método de pago" } } ×

            %button{ type: "button", data: { action: "click->order-form#addPaymentRow" }, class: "text-xs text-slate-600 hover:text-slate-900 font-medium flex items-center gap-1 mb-3" }
              %span.text-base +
              Agregar método de pago

            .rounded-lg.p-3.text-sm.bg-gray-50{ data: { order_form_target: "paymentSummary" } }
              .flex.justify-between.mb-1
                %span.text-gray-600 Total declarado
                %span.font-semibold{ data: { order_form_target: "paymentDeclared" } } $0
              %p.font-semibold.text-xs.mt-1{ data: { order_form_target: "paymentStatus" } }
```

- [ ] **Step 2: Verify the file parses (no Ruby syntax check needed — HAML compiles at request time)**

Open the form in the browser at `http://localhost:3000/web/orders/new` after starting Rails:

```bash
fish -l -c 'bin/rails server' &
sleep 5
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:3000/web/orders/new
```

Expected: redirect to login (302) — that's fine, the view renders past the parser.

(Manual visual check happens in Task 11.)

---

## Task 8: Extend `order_form_controller.js` for multi-row payments

**Files:**
- Modify: `app/javascript/controllers/order_form_controller.js`

- [ ] **Step 1: Update the targets list**

Replace line 4 with:

```javascript
  static targets = ["items", "total", "itemCount", "totalQuantity", "submitButton", "orderTypeInfo", "creditRadio", "immediateRadio", "paymentSection", "paymentSectionTitle", "paymentSectionSubtitle", "paymentSectionBadge", "paymentRows", "paymentRow", "paymentMethod", "paymentAmount", "paymentDeclared", "paymentStatus", "paymentSummary"]
```

- [ ] **Step 2: Replace `toggleCreditPaymentSection`, `updateInitialPayment`, and the bottom of `updateSummary` with new payment logic**

In `updateOrderType(event)`, replace the call `this.toggleCreditPaymentSection(orderType)` with `this.applyPaymentMode(orderType)`.

Remove the entire `toggleCreditPaymentSection` and `updateInitialPayment` methods.

Add these methods (place near the bottom, before `formatCurrency`):

```javascript
  applyPaymentMode(orderType) {
    if (!this.hasPaymentSectionTitleTarget) return

    if (orderType === "credit") {
      this.paymentSectionTitleTarget.textContent = "Cobro al Momento"
      this.paymentSectionSubtitleTarget.textContent = "Opcional — si el cliente paga algo ahora"
      this.paymentSectionBadgeTarget.textContent = "Opcional"
      this.paymentSectionBadgeTarget.classList.remove("bg-red-50", "text-red-700")
      this.paymentSectionBadgeTarget.classList.add("bg-gray-100", "text-gray-700")
    } else {
      this.paymentSectionTitleTarget.textContent = "Detalle de Pago"
      this.paymentSectionSubtitleTarget.textContent = "La suma debe coincidir con el total de la venta"
      this.paymentSectionBadgeTarget.textContent = "Requerido"
      this.paymentSectionBadgeTarget.classList.remove("bg-gray-100", "text-gray-700")
      this.paymentSectionBadgeTarget.classList.add("bg-red-50", "text-red-700")
    }
    this.updatePaymentTotal()
  }

  addPaymentRow() {
    const existingRows = this.paymentRowTargets
    const nextIndex = existingRows.length
    const template = existingRows[0].cloneNode(true)

    // Re-key name attributes
    template.querySelectorAll("[name]").forEach(el => {
      el.name = el.name.replace(/payments\[\d+\]/, `payments[${nextIndex}]`)
      if (el.tagName === "INPUT" && el.type === "number") el.value = ""
      if (el.tagName === "SELECT") el.selectedIndex = 0
    })

    this.paymentRowsTarget.appendChild(template)
    this.updatePaymentTotal()
  }

  removePaymentRow(event) {
    const row = event.target.closest("[data-order-form-target='paymentRow']")
    if (!row) return
    if (this.paymentRowTargets.length <= 1) {
      // Don't remove the last row; just clear it
      row.querySelector("input[type=number]").value = ""
      row.querySelector("select").selectedIndex = 0
    } else {
      row.remove()
      // Re-key remaining rows so indexes stay contiguous
      this.paymentRowTargets.forEach((r, i) => {
        r.querySelectorAll("[name]").forEach(el => {
          el.name = el.name.replace(/payments\[\d+\]/, `payments[${i}]`)
        })
      })
    }
    this.updatePaymentTotal()
  }

  updatePaymentTotal() {
    const total = this.calculateTotal()
    const declared = this.paymentAmountTargets.reduce((sum, input) => sum + (parseFloat(input.value) || 0), 0)
    const orderType = this.hasCreditRadioTarget && this.creditRadioTarget.checked ? "credit" : "immediate"

    if (this.hasPaymentDeclaredTarget) {
      this.paymentDeclaredTarget.textContent = `$${this.formatCurrency(declared)}`
    }

    let ok = true
    let statusText = ""
    let statusClass = "text-green-700"

    if (orderType === "immediate") {
      const matches = Math.abs(declared - total) < 0.01 && declared > 0
      ok = matches
      if (declared === 0) {
        statusText = "Cargá los métodos de pago"
        statusClass = "text-gray-500"
      } else if (declared < total) {
        statusText = `Faltan $${this.formatCurrency(total - declared)}`
        statusClass = "text-red-600"
      } else if (declared > total) {
        statusText = `Excede el total por $${this.formatCurrency(declared - total)}`
        statusClass = "text-red-600"
      } else {
        statusText = "✓ Coincide con el total"
        statusClass = "text-green-700"
      }
    } else {
      ok = declared <= total + 0.01
      if (declared === 0) {
        statusText = "Sin cobro al momento"
        statusClass = "text-gray-500"
      } else if (declared > total) {
        statusText = `Excede el total por $${this.formatCurrency(declared - total)}`
        statusClass = "text-red-600"
      } else {
        statusText = `Queda pendiente $${this.formatCurrency(total - declared)}`
        statusClass = "text-gray-700"
      }
    }

    if (this.hasPaymentStatusTarget) {
      this.paymentStatusTarget.textContent = statusText
      this.paymentStatusTarget.className = `font-semibold text-xs mt-1 ${statusClass}`
    }

    this.updateSubmitButton(ok)
  }

  updateSubmitButton(paymentsOk) {
    if (!this.hasSubmitButtonTarget) return
    const disabled = this.items.length === 0 || !paymentsOk
    this.submitButtonTarget.disabled = disabled
    if (disabled) {
      this.submitButtonTarget.classList.add("opacity-50", "cursor-not-allowed")
    } else {
      this.submitButtonTarget.classList.remove("opacity-50", "cursor-not-allowed")
    }
  }
```

- [ ] **Step 3: Replace the bottom of `updateSummary` (the submit-button block) with a call to `updatePaymentTotal()`**

In `updateSummary()`, REMOVE the entire `if (this.hasSubmitButtonTarget)` block at the end (lines ~310-328) and replace it with:

```javascript
    this.updatePaymentTotal()
```

- [ ] **Step 4: Initialize on `connect()`**

In `connect()`, after `this.applyCreditRadioState()`, add:

```javascript
    const initialOrderType = this.hasCreditRadioTarget && this.creditRadioTarget.checked ? "credit" : "immediate"
    this.applyPaymentMode(initialOrderType)
```

- [ ] **Step 5: Reload the form in the browser and visually verify**

This is a manual check — done in Task 11.

---

## Task 9: Drop the legacy `parse_payments` fallback in the controller

Now that the view sends `params[:payments]`, remove the old `initial_payment_*` branch.

**Files:**
- Modify: `app/controllers/web/orders_controller.rb`

- [ ] **Step 1: Simplify `parse_payments`**

Replace the method with the new shape only:

```ruby
def parse_payments
  return [] if params[:payments].blank?

  params[:payments].to_unsafe_h.values.filter_map do |entry|
    amount = entry[:amount].to_f
    next if amount <= 0
    { amount: amount, payment_method: entry[:payment_method].presence || "cash" }
  end
end
```

- [ ] **Step 2: Run the full suite + request specs**

```bash
fish -l -c 'bundle exec rspec spec/requests/web/orders_spec.rb'
```

Expected: existing examples may fail because they POST `initial_payment_amount` — Task 10 fixes them.

---

## Task 10: Update `spec/requests/web/orders_spec.rb` to the new param shape

**Files:**
- Modify: `spec/requests/web/orders_spec.rb`

- [ ] **Step 1: Rewrite the request specs**

Replace the whole `describe "POST /web/orders"` block:

```ruby
  describe "POST /web/orders" do
    let(:base_params) do
      {
        order: {
          customer_id: customer_with_credit.id,
          order_type: "credit",
          channel: "counter"
        },
        purchase_items: [
          { product_id: product.id, quantity: "2", unit_price: "100" }
        ],
        sale_date: Date.today.iso8601,
        paper_number: "0099"
      }
    end

    context "credit order with no payments" do
      it "creates Order and no Payment" do
        expect {
          post "/web/orders", params: base_params
        }.to change(Order, :count).by(1).and change(Payment, :count).by(0)
      end
    end

    context "credit order with a partial payment" do
      it "creates Order + 1 Payment + 1 Allocation" do
        params = base_params.merge(
          payments: { "0" => { amount: "50", payment_method: "cash" } }
        )
        expect {
          post "/web/orders", params: params
        }.to change(Order, :count).by(1)
          .and change(Payment, :count).by(1)
          .and change(PaymentAllocation, :count).by(1)

        order   = Order.order(:created_at).last
        payment = Payment.order(:created_at).last
        expect(payment.amount).to eq(50)
        expect(payment.payment_method).to eq("cash")
        expect(order.payment_allocations.first.payment_id).to eq(payment.id)
      end
    end

    context "immediate order with matching single payment" do
      it "creates Order + Payment + Allocation" do
        retail = create(:customer, has_credit_account: false, name: "Walk-in")
        params = base_params.deep_merge(
          order: { customer_id: retail.id, order_type: "immediate" }
        ).merge(
          payments: { "0" => { amount: "200", payment_method: "cash" } }
        )

        expect {
          post "/web/orders", params: params
        }.to change(Order, :count).by(1)
          .and change(Payment, :count).by(1)
          .and change(PaymentAllocation, :count).by(1)
      end
    end

    context "immediate order with split payments" do
      it "creates one Payment per method group" do
        retail = create(:customer, has_credit_account: false, name: "Walk-in")
        params = base_params.deep_merge(
          order: { customer_id: retail.id, order_type: "immediate" }
        ).merge(
          payments: {
            "0" => { amount: "120", payment_method: "cash" },
            "1" => { amount: "80",  payment_method: "transfer" }
          }
        )

        expect {
          post "/web/orders", params: params
        }.to change(Order, :count).by(1)
          .and change(Payment, :count).by(2)
          .and change(PaymentAllocation, :count).by(2)
      end
    end

    context "immediate order without payments" do
      it "fails and renders new" do
        retail = create(:customer, has_credit_account: false, name: "Walk-in")
        params = base_params.deep_merge(
          order: { customer_id: retail.id, order_type: "immediate" }
        )

        expect {
          post "/web/orders", params: params
        }.to change(Order, :count).by(0)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
```

- [ ] **Step 2: Run the request spec**

```bash
fish -l -c 'bundle exec rspec spec/requests/web/orders_spec.rb'
```

Expected: 0 failures.

- [ ] **Step 3: Run the full suite**

```bash
fish -l -c 'bundle exec rspec'
```

Expected: 0 new failures. Pre-existing date-drift failures may persist (≤5).

- [ ] **Step 4: Run rubocop**

```bash
fish -l -c 'bundle exec rubocop'
```

Expected: 0 offenses.

---

## Task 11: Manual smoke test in the browser

**Files:**
- None — pure verification.

- [ ] **Step 1: Boot the app**

```bash
fish -l -c 'bin/rails db:seed' # to refresh data with the new flow
fish -l -c 'bin/dev'
```

- [ ] **Step 2: Manual checklist (immediate sale)**

Open `http://localhost:3000/web/orders/new`. Sign in.

- Badge says "Requerido" (red)
- Add a product totalling $200
- Submit disabled (no payment yet)
- Add a $200 cash payment → submit enabled, status shows "✓ Coincide con el total"
- Change amount to $100 → submit disabled, status shows "Faltan $100"
- Click "+ Agregar método de pago" → second row appears
- Fill second row with $100 transfer → submit enabled
- Submit. Verify on orders index that the new sale appears; open it and confirm 2 Payments + 2 Allocations exist.

- [ ] **Step 3: Manual checklist (credit sale)**

- Select a customer with credit account (`Taller Mecánico El Rayo` from seeds)
- Switch to "Cuenta Corriente"
- Badge changes to "Opcional" (gray)
- No payment → submit enabled, status "Sin cobro al momento"
- Add a $50 cash payment for a $200 order → submit enabled, status "Queda pendiente $150"
- Submit. Verify the order has 1 Payment + 1 Allocation; customer balance shows $150.

- [ ] **Step 4: Edge case — switch order type back and forth**

- Add a payment, switch from immediate → credit → immediate. The form must remain usable; the badge updates each time.

---

## Task 12: Final verification + single commit

**Files:**
- Modify: `WORKING_CONTEXT.md` — update Customer account payments + Orders sections to describe the new flow.

- [ ] **Step 1: Update `WORKING_CONTEXT.md`**

Locate the `### Orders` section and the `### Customer account payments` section. Update them:

In `### Orders`, change:
> Created via **`Sales::CreateOrder`** (from `Web::OrdersController#create`).

To:
> Created via **`Sales::CreateOrder`** (from `Web::OrdersController#create`). Acepta `payments:` array — **obligatorio para `immediate`** (sum must equal `total_amount`), **opcional para `credit`** (sum must be `<= total_amount`). Cada entrada produce un `Payment` + `PaymentAllocation` apuntando a la nueva orden.

In `### Customer account payments`, change the `Sales::CreateOrder` reference (line that mentions `initial_payment:`) to:
> **`Sales::CreateOrder`** ahora crea Payments + Allocations para **ambos tipos** de orden vía el array `payments:`. Para órdenes immediate la suma debe igualar el total; para credit puede ser parcial o cero.

In `### Customer account payments`, update the `Customer#current_balance` description to:
> **`Customer#current_balance`** = `SUM(credit_orders.total_amount) − SUM(payment_allocations linked to credit orders)`. Payments de ventas immediate **no** afectan el balance de crédito.

- [ ] **Step 2: Run the full test suite + rubocop one final time**

```bash
fish -l -c 'bundle exec rspec'
fish -l -c 'bundle exec rubocop'
```

Expected: 0 new failures, 0 offenses.

- [ ] **Step 3: Stage and commit (single commit for the entire feature)**

```bash
git status
git diff --stat
```

Verify only the expected files are dirty. Then:

```bash
git add -A
git commit -m "feat(feat_07): payment method on all sales

- Drop Payment#customer_must_have_credit_account validation — Payment now represents
  any tender of money, retail-customer-friendly
- Customer#current_balance uses allocation-based formula — immediate-sale payments
  no longer offset credit debt
- Customer.with_outstanding_balance scope mirrors the same formula
- Sales::CreateOrder accepts payments: array (replaces initial_payment:):
  - immediate orders REQUIRE payments summing to total_amount
  - credit orders allow optional partial payments summing <= total_amount
- Web::OrdersController#parse_payments reads the indexed params[:payments] hash
- Order form: multi-row payment block visible for both order types, badge swaps
  Requerido (red) / Opcional (gray), live summary via Stimulus
- All existing specs migrated to payments: array; seeds.rb updated
- Update WORKING_CONTEXT.md

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

- [ ] **Step 4: Verify branch is clean**

```bash
git status
git log --oneline -1
```

Expected: clean tree, one new commit on `feat_07-payment-method-on-all-sales`.

---

## Self-review notes (already addressed)

- **Spec coverage:** Every spec section maps to at least one task (Payment validation → T2, Customer.current_balance + scope → T3/T4, CreateOrder payments → T5, controller → T6/T9, view → T7, Stimulus → T8, request specs → T10).
- **No placeholders:** All code blocks contain runnable code or exact transformations.
- **Type consistency:** `payments:` is consistently a keyword arg accepting `Array<{amount:, payment_method:}>` across service + controller + specs.
- **Backwards compatibility:** Task 5 Step 7 includes a temporary shim in the controller so the suite stays green during the transition; Task 9 removes it once the view (T7) and Stimulus (T8) are updated.
