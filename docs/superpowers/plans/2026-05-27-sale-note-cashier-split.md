# Sale Note / Cashier Split — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the sales flow into two roles. Vendor creates a *sale note* (cliente + productos + tipo + N° talonario, status `pending`). Cashier collects payment on immediate notes (global discount 0/5/10%, multi-tender, cash-only rule for discount). Credit notes flow unchanged through existing receivables; status auto-promotes to `confirmed` when balance reaches zero.

**Architecture:** Rails 7.2 + PostgreSQL + Hotwire (Stimulus) + HAML + Tailwind. Service objects return `Result`. Two cobro services: `Payments::AllocatePayment` (credit, existing, gains status promotion) and `Payments::CollectSaleNote` (immediate, new). Cashier UI lives at `/web/sale_notes`. Vendor form keeps its existing controller; we just remove the payment + discount blocks.

**Tech Stack:** Ruby on Rails 7.2, PostgreSQL, Devise, Pundit, RSpec, FactoryBot, Stimulus, HAML, Tailwind.

**Spec:** `docs/superpowers/specs/2026-05-27-sale-note-cashier-split-design.md`

**Commit policy:** No intermediate commits. Final task presents a single commit message for the user to apply manually.

---

## File Map

**Create:**
- `db/migrate/<timestamp>_add_pending_status_to_orders.rb` — change default to `pending`
- `app/services/payments/collect_sale_note.rb` — immediate cobro service
- `app/controllers/web/sale_notes_controller.rb` — list pending + cancel
- `app/controllers/web/sale_notes/payments_controller.rb` — cobro new/create
- `app/views/web/sale_notes/index.html.haml` — listing
- `app/views/web/sale_notes/payments/new.html.haml` — cobro form
- `app/javascript/controllers/sale_note_payment_controller.js` — Stimulus
- `app/policies/sale_note_policy.rb` — caja-only authorization
- `spec/services/payments/collect_sale_note_spec.rb`
- `spec/requests/web/sale_notes_spec.rb`
- `spec/requests/web/sale_notes/payments_spec.rb`
- `spec/policies/sale_note_policy_spec.rb`

**Modify:**
- `app/models/order.rb` — enum, validation, `outstanding_balance`, `refresh_status_from_balance!`
- `app/models/customer.rb` — `current_balance`, `with_outstanding_balance`
- `app/services/sales/create_order.rb` — drop payments + discount
- `app/services/payments/allocate_payment.rb` — accept pending; promote on full pay
- `app/controllers/web/orders_controller.rb` — drop payments + discount params
- `app/controllers/web/dashboard_controller.rb` — sales today + recent orders scopes
- `app/controllers/web/customers/payments_controller.rb` — filter `pending` credit
- `app/views/web/orders/new.html.haml` — drop discount + payment cards
- `app/views/web/orders/index.html.haml` — render pending badge
- `app/views/web/orders/show.html.haml` — accept pending state in conditionals
- `app/javascript/controllers/order_form_controller.js` — slim down
- `app/policies/order_policy.rb` — `cancel_pending?`
- `app/views/layouts/web/_sidebar.html.haml` — add "Notas de pedido" entry
- `config/routes.rb` — new `sale_notes` resource
- `spec/factories/orders.rb` — set `paper_number` default + add `:pending` trait
- `WORKING_CONTEXT.md` — fix stock claim, state machine, sale note flow

---

## Phase 1 — Order model: state machine + paper_number

### Task 1: Migration — change `status` default to `pending`

**Files:**
- Create: `db/migrate/<timestamp>_add_pending_status_to_orders.rb`

- [ ] **Step 1: Generate migration**

```bash
bin/rails generate migration AddPendingStatusToOrders
```

- [ ] **Step 2: Fill migration content**

```ruby
class AddPendingStatusToOrders < ActiveRecord::Migration[7.2]
  def change
    change_column_default :orders, :status, from: "confirmed", to: "pending"
  end
end
```

- [ ] **Step 3: Apply**

```bash
bin/rails db:migrate
```

Expected: migration runs, `schema.rb` updated. No data backfill (no production orders).

---

### Task 2: Update `Order` model — enum, validation, balance, status refresh

**Files:**
- Modify: `app/models/order.rb`

- [ ] **Step 1: Write failing model spec for new enum**

Add to `spec/models/order_spec.rb` (create if absent):

```ruby
require "rails_helper"

RSpec.describe Order, type: :model do
  describe "status enum" do
    it "defaults to pending" do
      order = build(:order, status: nil)
      expect(order.status).to eq("pending")
    end

    it "exposes pending_status? predicate" do
      expect(build(:order, status: "pending").pending_status?).to be true
    end
  end

  describe "#outstanding_balance" do
    it "is total_amount minus allocations for any non-cancelled order" do
      order = create(:order, :pending, total_amount: 1000)
      expect(order.outstanding_balance).to eq(1000)
    end

    it "is zero for cancelled orders regardless of balance" do
      order = create(:order, :pending, total_amount: 1000)
      order.update_column(:status, "cancelled")
      expect(order.outstanding_balance).to eq(0)
    end
  end

  describe "#refresh_status_from_balance!" do
    it "promotes pending to confirmed when balance reaches 0" do
      order = create(:order, :pending, total_amount: 1000)
      allow(order).to receive(:outstanding_balance).and_return(0)
      order.refresh_status_from_balance!
      expect(order.reload.status).to eq("confirmed")
    end

    it "keeps pending when balance > 0" do
      order = create(:order, :pending, total_amount: 1000)
      allow(order).to receive(:outstanding_balance).and_return(500)
      order.refresh_status_from_balance!
      expect(order.reload.status).to eq("pending")
    end

    it "is a no-op for cancelled orders" do
      order = create(:order, :pending, total_amount: 1000)
      order.update_column(:status, "cancelled")
      order.refresh_status_from_balance!
      expect(order.reload.status).to eq("cancelled")
    end
  end

  describe "paper_number validation" do
    it "is required for live orders" do
      order = build(:order, source: "live", paper_number: nil)
      expect(order).not_to be_valid
      expect(order.errors[:paper_number]).to include("can't be blank")
    end
  end
end
```

- [ ] **Step 2: Run spec to confirm failures**

```bash
bundle exec rspec spec/models/order_spec.rb
```

Expected: failures referencing the new enum value, `refresh_status_from_balance!`, and the broadened paper_number validation. (Some specs may pass already due to factory; the new ones must fail.)

- [ ] **Step 3: Update `app/models/order.rb`**

Replace the enum, scope, `outstanding_balance`, and validation blocks. Final file:

```ruby
class Order < ApplicationRecord
  belongs_to :customer, optional: true
  has_many :order_items, dependent: :destroy
  has_many :products, through: :order_items
  has_many :payment_allocations, dependent: :destroy
  has_many :payments, through: :payment_allocations
  has_many :stock_movements, as: :reference, dependent: :nullify

  accepts_nested_attributes_for :order_items, allow_destroy: true, reject_if: :all_blank

  enum :status, {
    pending:   "pending",
    confirmed: "confirmed",
    cancelled: "cancelled"
  }, suffix: true

  enum :order_type, {
    immediate: "immediate",
    credit:    "credit"
  }, suffix: true

  ALLOWED_CHANNELS = %w[counter whatsapp mercadolibre].freeze

  validates :order_type, presence: true
  validates :total_amount,
            numericality: { greater_than: 0 },
            unless: :from_paper?
  validates :total_amount,
            numericality: { greater_than_or_equal_to: 0 },
            if: :from_paper?
  validates :sale_date, presence: true
  validates :source, inclusion: { in: %w[live from_paper] }
  validates :channel, inclusion: { in: ALLOWED_CHANNELS, allow_nil: true }
  validates :paper_number, presence: true
  validate :credit_order_requires_credit_account
  validates :original_total_amount,
            presence: true,
            numericality: { greater_than_or_equal_to: 0 }
  validate :original_total_at_least_current_total

  scope :immediate, -> { where(order_type: "immediate") }
  scope :credit,    -> { where(order_type: "credit") }
  scope :pending,   -> { where(status: "pending") }
  scope :confirmed, -> { where(status: "confirmed") }
  scope :active,    -> { where.not(status: "cancelled") }
  scope :from_paper, -> { where(source: "from_paper") }
  scope :live,       -> { where(source: "live") }
  scope :by_sale_date, ->(date) { where(sale_date: date) if date.present? }

  def outstanding_balance
    return 0 if cancelled_status?
    total_amount - payment_allocations.sum(:amount)
  end

  def from_paper?
    source == "from_paper"
  end

  def live?
    source == "live"
  end

  def calculate_total!
    update!(total_amount: order_items.sum("quantity * unit_price"))
  end

  def discount_amount
    return 0 if original_total_amount.nil? || total_amount.nil?
    original_total_amount - total_amount
  end

  def discount_percent_display
    order_items.first&.discount_percent.to_i
  end

  # Promote to confirmed when fully paid; revert to pending if balance reappears.
  # No-op on cancelled orders.
  def refresh_status_from_balance!
    return if cancelled_status?
    new_status = outstanding_balance <= 0 ? "confirmed" : "pending"
    update!(status: new_status) if status != new_status
  end

  def cancel!(reason: nil)
    result = Sales::CancelOrder.call(order: self, reason: reason)

    if result.success?
      result.record
    else
      raise StandardError, result.errors.join(", ")
    end
  end

  private

  def credit_order_requires_credit_account
    return unless credit_order_type?
    return if customer.nil?

    unless customer.has_credit_account?
      errors.add(:base, "Credit orders require a customer with credit account enabled")
    end
  end

  def original_total_at_least_current_total
    return if original_total_amount.nil? || total_amount.nil?
    if original_total_amount < total_amount
      errors.add(:original_total_amount, "no puede ser menor al total actual")
    end
  end
end
```

- [ ] **Step 4: Run model spec again**

```bash
bundle exec rspec spec/models/order_spec.rb
```

Expected: all new examples pass. Some existing examples may still fail due to factory not setting `paper_number` for non-paper variants — Task 3 fixes the factory.

---

### Task 3: Update `Order` factory — `paper_number` default + `:pending` trait

**Files:**
- Modify: `spec/factories/orders.rb`

- [ ] **Step 1: Read current factory**

```bash
cat spec/factories/orders.rb
```

- [ ] **Step 2: Update factory**

Apply two changes:

```ruby
factory :order do
  customer { Customer.mostrador }
  status { "confirmed" }                # leave default confirmed for existing tests
  order_type { "immediate" }
  total_amount { 100.0 }
  original_total_amount { total_amount }
  channel { nil }
  source { "live" }
  sale_date { Date.today }
  sequence(:paper_number) { |n| format("A-%04d", n) }   # NEW — required now

  trait :pending do                                     # NEW — for plan use
    status { "pending" }
  end

  # ... keep existing traits as-is. The `from_paper` trait already sets
  # paper_number — leave it; the sequence default is overridden by the trait.
end
```

- [ ] **Step 3: Rerun model spec**

```bash
bundle exec rspec spec/models/order_spec.rb
```

Expected: all pass.

- [ ] **Step 4: Rerun full suite to catch fallout**

```bash
bundle exec rspec
```

Expected: any prior failures unrelated to paper_number are now visible. If a prior test sets `status: "confirmed"` and expects behaviour from a no-allocation state, it still works (factory default is confirmed). Specs that touched `Order#outstanding_balance` for immediate orders may now show non-zero values — fix them by treating immediate as also having a balance, or by adjusting the test setup.

If failures remain, fix them in place. Common cases:
- Spec expects `order.outstanding_balance == 0` for an immediate confirmed order with no allocations: now returns `total_amount`. Fix the test expectation (or create allocations to match).
- Spec calling `Sales::CreateOrder` with `payments:` or `discount_percent:` keyword args: those will be removed in Task 4 — leave for now, expect failures to remain until that task.

---

## Phase 2 — Vendor flow: simplify `Sales::CreateOrder` and form

### Task 4: Slim down `Sales::CreateOrder`

**Files:**
- Modify: `app/services/sales/create_order.rb`
- Modify: `spec/services/sales/create_order_spec.rb`

- [ ] **Step 1: Write failing specs for new behaviour**

In `spec/services/sales/create_order_spec.rb`, ensure the file contains (replace conflicting examples):

```ruby
require "rails_helper"

RSpec.describe Sales::CreateOrder do
  let(:product) { create(:product, current_stock: 10, price_unit: 100) }
  let(:customer) { create(:customer, :with_credit) }

  describe ".call" do
    it "creates an order in pending status with no payments or discount" do
      result = described_class.call(
        customer: customer,
        order_type: "credit",
        paper_number: "A-0001",
        items: [{ product_id: product.id, quantity: 2 }]
      )

      expect(result).to be_success
      order = result.record
      expect(order.status).to eq("pending")
      expect(order.total_amount).to eq(200)
      expect(order.original_total_amount).to eq(200)
      expect(order.payment_allocations).to be_empty
      expect(order.order_items.first.discount_percent).to eq(0)
    end

    it "requires paper_number for live orders" do
      result = described_class.call(
        customer: customer,
        order_type: "credit",
        paper_number: nil,
        items: [{ product_id: product.id, quantity: 1 }]
      )

      expect(result).to be_failure
      expect(result.errors.join).to match(/talonario|paper/i)
    end

    it "does not accept payments: keyword" do
      expect(described_class.method(:call).parameters.map(&:last)).not_to include(:payments)
    end

    it "does not accept discount_percent: keyword" do
      expect(described_class.method(:call).parameters.map(&:last)).not_to include(:discount_percent)
    end
  end
end
```

- [ ] **Step 2: Run spec to confirm failures**

```bash
bundle exec rspec spec/services/sales/create_order_spec.rb
```

Expected: failures.

- [ ] **Step 3: Replace `app/services/sales/create_order.rb`**

```ruby
module Sales
  # Sales::CreateOrder
  #
  # Creates a sale note (Order) in `pending` status. Vendor-facing entry point:
  # no payments, no discount, no stock movements (verified: stock changes are
  # not applied at sale time today).
  #
  # Modes:
  #   - LIVE (default): prices from DB, validates stock availability
  #   - FROM_PAPER:     unit_price may be nil, total may be 0,
  #                     requires paper_number, no stock validation
  class CreateOrder
    Item = Struct.new(:product_id, :quantity, :unit_price, keyword_init: true)

    def self.call(customer:, items:, order_type:, paper_number:, channel: nil,
                  source: "live", sale_date: nil)
      new(
        customer: customer,
        items: items,
        order_type: order_type,
        paper_number: paper_number,
        channel: channel,
        source: source,
        sale_date: sale_date
      ).call
    end

    def initialize(customer:, items:, order_type:, paper_number:, channel: nil,
                   source: "live", sale_date: nil)
      @customer     = customer
      @items        = items.map { |i| i.is_a?(Item) ? i : Item.new(i) }
      @order_type   = order_type
      @paper_number = paper_number.presence
      @channel      = channel
      @source       = source
      @sale_date    = sale_date || Date.today
    end

    def call
      validate_params

      ActiveRecord::Base.transaction do
        create_order
        create_order_items
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

    def validate_params
      unless %w[immediate credit].include?(@order_type)
        raise ValidationError, "Invalid order type"
      end

      raise ValidationError, "Customer is required" if @customer.nil?
      raise ValidationError, "N° de talonario es requerido" if @paper_number.nil?

      if @order_type == "credit" && !@customer.has_credit_account?
        raise ValidationError, "Customer does not have credit account enabled"
      end

      raise ValidationError, "At least one product is required" if @items.blank?

      @items.each do |item|
        raise ValidationError, "Product ID is required" unless item.product_id
        raise ValidationError, "Quantity must be greater than zero" unless item.quantity.to_i > 0
      end

      return if @source == "from_paper"

      @items.each do |item|
        product = Product.find(item.product_id)
        if product.current_stock < item.quantity
          raise ValidationError, "Insufficient stock for #{product.name}. Available: #{product.current_stock}"
        end
      end
    end

    def create_order
      total = calculate_total
      @order = Order.create!(
        customer:              @customer,
        order_type:            @order_type,
        channel:               @channel,
        source:                @source,
        sale_date:             @sale_date,
        paper_number:          @paper_number,
        status:                "pending",
        total_amount:          total,
        original_total_amount: total
      )
    end

    def calculate_total
      @calculate_total ||= @items.sum do |item|
        product    = Product.find(item.product_id)
        unit_price = item.unit_price || product.price_unit || 0
        item.quantity * unit_price
      end
    end

    def create_order_items
      @items.each do |item|
        product     = Product.find(item.product_id)
        final_price = item.unit_price || product.price_unit || 0

        OrderItem.create!(
          order:            @order,
          product:          product,
          quantity:         item.quantity,
          unit_price:       final_price,
          discount_percent: 0
        )
      end
    end
  end
end
```

- [ ] **Step 4: Run spec to confirm green**

```bash
bundle exec rspec spec/services/sales/create_order_spec.rb
```

Expected: pass.

---

### Task 5: Update `Web::OrdersController#create` and form

**Files:**
- Modify: `app/controllers/web/orders_controller.rb`
- Modify: `app/views/web/orders/new.html.haml`

- [ ] **Step 1: Update controller `create` action**

In `app/controllers/web/orders_controller.rb`, replace the body of `create` and delete the `parse_payments` private method:

```ruby
def create
  authorize Order, :create?
  result = Sales::CreateOrder.call(
    customer:     find_or_create_customer,
    items:        parse_items,
    order_type:   params.dig(:order, :order_type) || "immediate",
    channel:      params.dig(:order, :channel),
    source:       params[:source] || "live",
    sale_date:    params[:sale_date],
    paper_number: params[:paper_number]
  )

  if result.success?
    redirect_to web_order_path(result.record),
                notice: "Nota ##{result.record.id} creada — pendiente de cobro"
  else
    flash.now[:alert] = result.errors.join(", ")
    @order = Order.new
    render :new, status: :unprocessable_entity
  end
end
```

Delete the entire `parse_payments` private method.

- [ ] **Step 2: Remove `source: 'from_paper'` hidden field hack**

The form currently does `= hidden_field_tag :source, 'from_paper'` — this forces every vendor-created order to `from_paper`. Remove that line; `source` defaults to `"live"` in the controller already.

In `app/views/web/orders/new.html.haml`, delete:

```haml
-# Hidden fields para ventas-lite
= hidden_field_tag :source, 'from_paper'
```

- [ ] **Step 3: Remove Descuento card from form**

In `app/views/web/orders/new.html.haml`, delete the entire block starting with the comment `-# ============ CARD - Descuento` through the matching closing card (the `select_tag :discount_percent` block).

- [ ] **Step 4: Remove Detalle de Pago card from form**

Delete the entire block starting with `-# ============ CARD - Detalle de Pago` through the closing of that card (including the `paymentSummary` div).

- [ ] **Step 5: Update summary card text to reflect new flow**

In the right-side "Resumen de Venta" card, replace the `-# Desglose de pago` block and the `-# Desglose descuento` block with a single helper line:

Delete:
```haml
-# Desglose descuento (solo visible cuando discount > 0)
.border-t.border-gray-200.py-4.hidden{ data: { order_form_target: "summaryDiscountRow" } }
  ...
-# Desglose de pago (solo visible en venta a crédito)
.border-t.border-gray-200.py-4.hidden{ data: { order_form_target: "summaryBreakdown" } }
  ...
```

Replace the submit-area helper text:

```haml
.mt-4.text-center
  %p.text-xs.text-gray-500 La nota queda pendiente de cobro
```

Update submit label:

```haml
= f.submit "Crear nota de pedido", disabled: true, class: "...", data: { order_form_target: "submitButton" }
```

- [ ] **Step 6: Manually verify the form renders**

```bash
bin/rails server
```

Open http://localhost:3000/web/orders/new, log in as a vendor (or admin), and confirm:
- No "Descuento" card
- No "Detalle de Pago" card
- "N° Talonario" input is present and required
- Submit button text is "Crear nota de pedido"

Stop the server.

---

### Task 6: Slim down `order_form_controller.js`

**Files:**
- Modify: `app/javascript/controllers/order_form_controller.js`

- [ ] **Step 1: Read full controller**

```bash
cat app/javascript/controllers/order_form_controller.js
```

- [ ] **Step 2: Remove dead targets and methods**

In the `static targets = [...]` array, delete these target names (they correspond to DOM that no longer exists):

`paymentSection`, `paymentSectionTitle`, `paymentSectionSubtitle`, `paymentSectionBadge`, `paymentRows`, `paymentRow`, `paymentMethod`, `paymentAmount`, `paymentDeclared`, `paymentStatus`, `paymentSummary`, `summaryBreakdown`, `summaryPaidNow`, `summaryOutstanding`, `discountSelect`, `discountCard`, `summaryDiscountRow`, `summarySubtotal`, `summaryDiscount`, `summaryDiscountLabel`

Then delete any method whose body references *only* those removed targets:

`addPaymentRow`, `removePaymentRow`, `updatePaymentTotal`, `discountChanged`, and any helper that calls them.

Inside surviving methods (`updateOrderType`, `customerChanged`, `addProduct`, `removeProduct`, `updateQuantity`, `renderSummary`, etc.), delete the lines that read or write removed targets. The submit-enable logic should now depend only on: items present + customer valid + order_type valid.

- [ ] **Step 3: Reload the form in browser**

```bash
bin/rails server
```

Open the form, add a product, switch between Contado / Cuenta Corriente. Verify:
- No JS errors in console (browser dev tools)
- Submit button enables when at least one product is present
- Adding items updates the running total

Stop the server.

---

## Phase 3 — Credit cobro auto-promotion + downstream scopes

### Task 7: `Payments::AllocatePayment` — accept pending credit + promote status

**Files:**
- Modify: `app/services/payments/allocate_payment.rb`
- Modify: `spec/services/payments/allocate_payment_spec.rb`

- [ ] **Step 1: Write failing specs**

Add to `spec/services/payments/allocate_payment_spec.rb`:

```ruby
describe "status promotion" do
  let(:customer) { create(:customer, :with_credit) }
  let(:order) { create(:order, :credit_order, :pending, customer: customer, total_amount: 1000, original_total_amount: 1000) }

  it "accepts a pending credit order" do
    result = described_class.call(
      customer: customer,
      payment_date: Date.today,
      allocations: [{ order_id: order.id, amount: 400, payment_method: "cash" }]
    )

    expect(result).to be_success
    expect(order.reload.status).to eq("pending")
  end

  it "promotes the order to confirmed when fully paid" do
    described_class.call(
      customer: customer,
      payment_date: Date.today,
      allocations: [{ order_id: order.id, amount: 1000, payment_method: "cash" }]
    )

    expect(order.reload.status).to eq("confirmed")
  end
end
```

- [ ] **Step 2: Run spec to confirm failure**

```bash
bundle exec rspec spec/services/payments/allocate_payment_spec.rb
```

Expected: first example fails on `unless order.credit_order_type? && order.confirmed_status?`. Second fails because no promotion happens yet.

- [ ] **Step 3: Update validation and add promotion**

In `app/services/payments/allocate_payment.rb`, replace this check inside `validate_params`:

```ruby
unless order.credit_order_type? && order.confirmed_status?
  raise ValidationError, "La orden ##{order.id} no es una venta a crédito confirmada"
end
```

with:

```ruby
unless order.credit_order_type? && !order.cancelled_status?
  raise ValidationError, "La orden ##{order.id} no es una venta a crédito activa"
end
```

Then, at the end of the transaction body in `#call` (right before `Result.new(success?: true, ...)`), add:

```ruby
@allocations.map { |row| row[:order_id] }.uniq.each do |oid|
  Order.find(oid).refresh_status_from_balance!
end
```

- [ ] **Step 4: Run spec**

```bash
bundle exec rspec spec/services/payments/allocate_payment_spec.rb
```

Expected: pass.

---

### Task 8: Update `Customer` scopes to include `pending` credit

**Files:**
- Modify: `app/models/customer.rb`
- Modify: `spec/models/customer_spec.rb` (if it exists; otherwise add what's needed)

- [ ] **Step 1: Write failing spec**

Add to `spec/models/customer_spec.rb`:

```ruby
describe "#current_balance" do
  it "includes pending credit orders" do
    customer = create(:customer, :with_credit)
    create(:order, :credit_order, :pending, customer: customer, total_amount: 500, original_total_amount: 500)
    expect(customer.current_balance).to eq(500)
  end
end

describe ".with_outstanding_balance" do
  it "includes customers with pending credit orders and no allocations" do
    customer = create(:customer, :with_credit)
    create(:order, :credit_order, :pending, customer: customer, total_amount: 500, original_total_amount: 500)
    expect(described_class.with_outstanding_balance).to include(customer)
  end
end
```

- [ ] **Step 2: Run spec to confirm failure**

```bash
bundle exec rspec spec/models/customer_spec.rb
```

- [ ] **Step 3: Update `Customer`**

In `app/models/customer.rb`, change both queries to use `status IN ('pending', 'confirmed')`:

Replace `with_outstanding_balance`:

```ruby
scope :with_outstanding_balance, -> {
  with_credit_account.where(
    "( SELECT COALESCE(SUM(o.total_amount), 0)
       FROM orders o
       WHERE o.customer_id = customers.id
         AND o.order_type = 'credit'
         AND o.status IN ('pending', 'confirmed') )
     >
     ( SELECT COALESCE(SUM(pa.amount), 0)
       FROM payment_allocations pa
       JOIN orders o ON pa.order_id = o.id
       WHERE o.customer_id = customers.id
         AND o.order_type = 'credit'
         AND o.status IN ('pending', 'confirmed') )"
  )
}
```

Replace `current_balance`:

```ruby
def current_balance
  return 0 unless has_credit_account?

  credit_owed = orders
                  .where(order_type: "credit", status: %w[pending confirmed])
                  .sum(:total_amount)

  credit_paid = PaymentAllocation
                  .joins(:order)
                  .where(orders: { customer_id: id, order_type: "credit", status: %w[pending confirmed] })
                  .sum(:amount)

  credit_owed - credit_paid
end
```

- [ ] **Step 4: Run spec**

```bash
bundle exec rspec spec/models/customer_spec.rb
```

Expected: pass.

---

### Task 9: Update `DashboardController` scopes

**Files:**
- Modify: `app/controllers/web/dashboard_controller.rb`

- [ ] **Step 1: Replace `Order.confirmed_status` with `Order.active` in this file**

In `app/controllers/web/dashboard_controller.rb`:

```ruby
def index
  authorize :dashboard, :index?
  @sales_today        = calculate_sales_today
  @low_stock_count    = Product.with_low_stock.count
  @total_receivable   = calculate_total_receivable
  @invoices_this_month = calculate_invoices_this_month

  @recent_orders = Order.active
                        .order(created_at: :desc)
                        .limit(5)
                        .includes(:customer)

  @low_stock_products = Product.with_low_stock.order(:current_stock).limit(10)
end

private

def calculate_sales_today
  Order.active
       .where(created_at: Date.today.all_day)
       .sum(:total_amount)
end
```

(Leave `Invoice.where(status: "confirmed")` alone — it's a separate concern.)

- [ ] **Step 2: Manual smoke check**

```bash
bin/rails server
```

Open `/web/dashboard`, confirm metrics render (no error). Stop server.

---

### Task 10: Update receivables filter

**Files:**
- Modify: `app/controllers/web/customers/payments_controller.rb`

- [ ] **Step 1: Replace both occurrences of `.where(status: "confirmed")`**

In `app/controllers/web/customers/payments_controller.rb`, both in `#new` and the error branch of `#create`, change:

```ruby
.where(status: "confirmed")
```

to:

```ruby
.where(status: %w[pending confirmed])
```

(The `select { |o| o.outstanding_balance > 0 }` filter still narrows down correctly. With auto-promotion, fully-paid orders are `confirmed` with `outstanding_balance == 0` and get filtered out. Unpaid/partial stay `pending` and are included.)

- [ ] **Step 2: Run receivables request spec**

```bash
bundle exec rspec spec/requests/web/customers/payments_spec.rb
```

Expected: pass. If failures, they probably hard-code `confirmed` somewhere in setup — fix to use `:pending` trait or whatever the test intends.

---

### Task 11: Update `OrdersController` and views that hard-check `confirmed_status?`

**Files:**
- Modify: `app/views/web/orders/index.html.haml`
- Modify: `app/views/web/orders/show.html.haml`

- [ ] **Step 1: Audit usages**

```bash
grep -n "confirmed_status?\|pending_status?" app/views/web/orders/*.haml
```

- [ ] **Step 2: For each branch, decide intent**

In `app/views/web/orders/index.html.haml` and `show.html.haml`, every `if order.confirmed_status?` / `if @order.confirmed_status?` block currently means "this is a real sale, not cancelled". After the refactor, that intent is "not cancelled" → use `active_status?` is not a predicate; the equivalent is `!cancelled_status?`.

Replace each `confirmed_status?` reference with `!cancelled_status?` (or `!@order.cancelled_status?`), **unless** the surrounding context specifically requires fully-paid (no current site does — confirmed historically meant "real sale").

For the status badge rendering, distinguish three colors:
- `pending_status?` → amber/yellow badge "Pendiente"
- `confirmed_status?` → green badge "Confirmada"
- `cancelled_status?` → red badge "Cancelada"

Example index badge block:

```haml
- if order.pending_status?
  %span.px-2.py-1.rounded.bg-amber-100.text-amber-800.text-xs.font-semibold
    Pendiente
- elsif order.confirmed_status?
  %span.px-2.py-1.rounded.bg-emerald-100.text-emerald-800.text-xs.font-semibold
    Confirmada
- else
  %span.px-2.py-1.rounded.bg-red-100.text-red-800.text-xs.font-semibold
    Cancelada
```

Apply equivalent edits in `show.html.haml`.

- [ ] **Step 3: Manual smoke**

Boot server, visit `/web/orders` and any order's show page, confirm rendering for a pending order works.

---

## Phase 4 — Cashier flow

### Task 12: `Payments::CollectSaleNote` service

**Files:**
- Create: `app/services/payments/collect_sale_note.rb`
- Create: `spec/services/payments/collect_sale_note_spec.rb`

- [ ] **Step 1: Write failing spec**

```ruby
require "rails_helper"

RSpec.describe Payments::CollectSaleNote do
  let(:customer) { Customer.mostrador }
  let(:product)  { create(:product, current_stock: 10, price_unit: 100) }
  let(:order) do
    create(:order, :pending,
           customer: customer,
           order_type: "immediate",
           total_amount: 1000,
           original_total_amount: 1000).tap do |o|
      create(:order_item, order: o, product: product, quantity: 10, unit_price: 100, discount_percent: 0)
    end
  end

  describe ".call" do
    it "creates payment + allocation and promotes order to confirmed when paid exactly" do
      result = described_class.call(
        order: order,
        discount_percent: 0,
        tenders: [{ payment_method: "cash", amount: 1000 }]
      )

      expect(result).to be_success
      expect(order.reload.status).to eq("confirmed")
      expect(order.payment_allocations.count).to eq(1)
      expect(order.payment_allocations.first.amount).to eq(1000)
    end

    it "applies global discount and recalculates total when 100% cash and exact" do
      result = described_class.call(
        order: order,
        discount_percent: 5,
        tenders: [{ payment_method: "cash", amount: 950 }]
      )

      expect(result).to be_success
      expect(order.reload.total_amount).to eq(950)
      expect(order.original_total_amount).to eq(1000)
      expect(order.order_items.first.discount_percent).to eq(5)
    end

    it "rejects discount when any tender is non-cash" do
      result = described_class.call(
        order: order,
        discount_percent: 5,
        tenders: [
          { payment_method: "cash", amount: 500 },
          { payment_method: "transfer", amount: 450 }
        ]
      )

      expect(result).to be_failure
      expect(result.errors.join).to match(/efectivo/i)
    end

    it "rejects discount when cash tender total != new total" do
      result = described_class.call(
        order: order,
        discount_percent: 5,
        tenders: [{ payment_method: "cash", amount: 800 }]
      )

      expect(result).to be_failure
    end

    it "rejects when tender sum != effective total (no discount)" do
      result = described_class.call(
        order: order,
        discount_percent: 0,
        tenders: [{ payment_method: "cash", amount: 999 }]
      )

      expect(result).to be_failure
    end

    it "rejects credit orders" do
      credit = create(:order, :credit_order, :pending, paper_number: "A-9999", total_amount: 100, original_total_amount: 100)
      result = described_class.call(
        order: credit,
        discount_percent: 0,
        tenders: [{ payment_method: "cash", amount: 100 }]
      )

      expect(result).to be_failure
    end

    it "rejects already-confirmed orders" do
      order.update_column(:status, "confirmed")
      result = described_class.call(
        order: order,
        discount_percent: 0,
        tenders: [{ payment_method: "cash", amount: 1000 }]
      )

      expect(result).to be_failure
    end

    it "groups multi-tender mix into one Payment per method" do
      result = described_class.call(
        order: order,
        discount_percent: 0,
        tenders: [
          { payment_method: "cash", amount: 600 },
          { payment_method: "transfer", amount: 400 }
        ]
      )

      expect(result).to be_success
      payments = order.payment_allocations.map(&:payment).uniq
      expect(payments.size).to eq(2)
      expect(payments.map(&:payment_method)).to contain_exactly("cash", "transfer")
    end
  end
end
```

- [ ] **Step 2: Run spec to confirm class missing**

```bash
bundle exec rspec spec/services/payments/collect_sale_note_spec.rb
```

Expected: `NameError: uninitialized constant Payments::CollectSaleNote`.

- [ ] **Step 3: Create service**

`app/services/payments/collect_sale_note.rb`:

```ruby
# frozen_string_literal: true

module Payments
  # Collects payment on an immediate sale note (the cashier flow).
  #
  # Rules:
  #   - Order must be immediate + pending.
  #   - discount_percent ∈ {0, 5, 10}; distributed to each order_item.
  #   - Tenders sum to effective total (original_total * (1 - discount/100)).
  #   - If discount > 0, every tender must be `cash` AND cover full total.
  class CollectSaleNote
    TOLERANCE = 0.01
    ALLOWED_DISCOUNTS = [0, 5, 10].freeze

    def self.call(order:, tenders:, discount_percent: 0, payment_date: Date.today)
      new(
        order: order,
        tenders: tenders,
        discount_percent: discount_percent,
        payment_date: payment_date
      ).call
    end

    def initialize(order:, tenders:, discount_percent:, payment_date:)
      @order            = order
      @tenders          = Array(tenders).map { |t| t.to_h.symbolize_keys }
      @discount_percent = discount_percent.to_i
      @payment_date     = payment_date || Date.today
    end

    def call
      validate!

      ActiveRecord::Base.transaction do
        apply_discount!
        create_payments_and_allocations!
        @order.refresh_status_from_balance!

        Result.new(success?: true, record: @order, errors: [])
      end
    rescue ValidationError => e
      Result.new(success?: false, record: nil, errors: [ e.message ])
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, record: nil, errors: e.record.errors.full_messages)
    rescue StandardError => e
      Rails.logger.error("Error in Payments::CollectSaleNote: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      Result.new(success?: false, record: nil, errors: [ "Error registrando el cobro" ])
    end

    private

    class ValidationError < StandardError; end

    def validate!
      unless @order.immediate_order_type? && @order.pending_status?
        raise ValidationError, "La nota no está pendiente o no es inmediata"
      end

      unless ALLOWED_DISCOUNTS.include?(@discount_percent)
        raise ValidationError, "Descuento inválido (0, 5 o 10)"
      end

      raise ValidationError, "Debe incluir al menos un pago" if @tenders.empty?

      @tenders.each do |t|
        amount = t[:amount].to_f
        raise ValidationError, "El monto debe ser mayor a cero" if amount <= 0
        unless Payment::PAYMENT_METHODS.include?(t[:payment_method])
          raise ValidationError, "Método de pago inválido: #{t[:payment_method]}"
        end
      end

      tender_sum = @tenders.sum { |t| t[:amount].to_f }

      if @discount_percent.positive?
        non_cash = @tenders.any? { |t| t[:payment_method] != "cash" }
        if non_cash || (tender_sum - effective_total).abs > TOLERANCE
          raise ValidationError, "Descuento solo permitido si el total se paga en efectivo"
        end
      else
        if (tender_sum - effective_total).abs > TOLERANCE
          raise ValidationError, "La suma de los pagos ($#{tender_sum}) debe coincidir con el total ($#{effective_total})"
        end
      end
    end

    def effective_total
      @effective_total ||= (@order.original_total_amount.to_d * (1 - @discount_percent.to_d / 100)).round(2)
    end

    def apply_discount!
      return if @discount_percent.zero?

      @order.order_items.each do |item|
        item.update!(discount_percent: @discount_percent)
      end

      new_total = @order.order_items.reload.sum do |oi|
        unit            = (oi.unit_price || 0).to_d
        discount_factor = 1 - oi.discount_percent.to_d / 100
        (unit * oi.quantity * discount_factor).round(2)
      end
      @order.update!(total_amount: new_total)
    end

    def create_payments_and_allocations!
      @tenders.group_by { |t| t[:payment_method] }.each do |method, rows|
        total = rows.sum { |r| r[:amount].to_f }
        payment = Payment.create!(
          customer:       @order.customer,
          amount:         total,
          payment_method: method,
          payment_date:   @payment_date
        )
        rows.each do |row|
          PaymentAllocation.create!(
            payment: payment,
            order:   @order,
            amount:  row[:amount].to_f
          )
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run spec**

```bash
bundle exec rspec spec/services/payments/collect_sale_note_spec.rb
```

Expected: pass.

---

### Task 13: Routes for `sale_notes` resource

**Files:**
- Modify: `config/routes.rb`

- [ ] **Step 1: Add inside `namespace :web do ... end`**

```ruby
resources :sale_notes, only: [ :index ] do
  resource :payment, only: [ :new, :create ],
                     controller: "sale_notes/payments"
  member do
    post :cancel
  end
end
```

- [ ] **Step 2: Verify routes**

```bash
bin/rails routes | grep sale_notes
```

Expected:
```
web_sale_notes        GET   /web/sale_notes(.:format)
cancel_web_sale_note  POST  /web/sale_notes/:id/cancel(.:format)
web_sale_note_payment POST  /web/sale_notes/:sale_note_id/payment(.:format)
new_web_sale_note_payment GET /web/sale_notes/:sale_note_id/payment/new(.:format)
```

---

### Task 14: `Web::SaleNotesController`

**Files:**
- Create: `app/controllers/web/sale_notes_controller.rb`
- Create: `app/policies/sale_note_policy.rb`

- [ ] **Step 1: Create policy**

`app/policies/sale_note_policy.rb`:

```ruby
# frozen_string_literal: true

# Pundit policy used by Web::SaleNotesController and the nested payments
# controller. The "record" is an Order (we don't introduce a separate model).
class SaleNotePolicy < ApplicationPolicy
  def index?
    user.caja? || user.admin?
  end

  def collect?
    (user.caja? || user.admin?) && record.immediate_order_type? && record.pending_status?
  end

  def cancel?
    record.pending_status? && (user.vendedor? || user.caja? || user.admin?)
  end
end
```

- [ ] **Step 2: Create controller**

`app/controllers/web/sale_notes_controller.rb`:

```ruby
module Web
  class SaleNotesController < ApplicationController
    def index
      authorize Order, :index?, policy_class: SaleNotePolicy
      @notes = Order.immediate.pending
                    .includes(:customer, order_items: :product)
                    .order(created_at: :asc)
    end

    def cancel
      @note = Order.find(params[:id])
      authorize @note, :cancel?, policy_class: SaleNotePolicy

      result = Sales::CancelOrder.call(order: @note, reason: "Cancelada desde caja")

      if result.success?
        redirect_to web_sale_notes_path, notice: "Nota ##{@note.id} cancelada"
      else
        redirect_to web_sale_notes_path, alert: result.errors.join(", ")
      end
    end
  end
end
```

- [ ] **Step 3: Write request spec**

`spec/requests/web/sale_notes_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Web::SaleNotes", type: :request do
  let(:cashier) { create(:user, role: "caja") }
  let(:vendor)  { create(:user, role: "vendedor") }

  describe "GET /web/sale_notes" do
    it "renders pending immediate orders for cashier" do
      sign_in cashier
      product = create(:product, current_stock: 5, price_unit: 100)
      note = create(:order, :pending, order_type: "immediate", paper_number: "A-1000", total_amount: 100, original_total_amount: 100)

      get "/web/sale_notes"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("A-1000")
    end

    it "forbids vendor access" do
      sign_in vendor
      get "/web/sale_notes"
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "POST /web/sale_notes/:id/cancel" do
    it "cancels a pending note" do
      sign_in cashier
      note = create(:order, :pending, order_type: "immediate", paper_number: "A-1001", total_amount: 100, original_total_amount: 100)

      post "/web/sale_notes/#{note.id}/cancel"
      expect(note.reload.status).to eq("cancelled")
    end
  end
end
```

- [ ] **Step 4: Run spec**

```bash
bundle exec rspec spec/requests/web/sale_notes_spec.rb
```

Expected: pass.

---

### Task 15: Sale notes index view

**Files:**
- Create: `app/views/web/sale_notes/index.html.haml`

- [ ] **Step 1: Create view**

```haml
- content_for :page_title, "Notas de pedido"

.container.mx-auto.px-6.py-6

  .flex.items-baseline.justify-between.mb-6
    %h1.text-2xl.font-semibold.text-slate-900 Notas de pedido
    %span.text-sm.text-slate-500 Pendientes de cobro

  - if @notes.empty?
    .bg-white.border.border-slate-200.rounded-2xl.p-12.text-center
      %p.text-slate-600 No hay notas pendientes de cobro.
  - else
    .bg-white.border.border-slate-200.rounded-2xl.overflow-hidden
      - @notes.each_with_index do |note, idx|
        .flex.items-center.gap-6.px-5.py-4{ class: idx < @notes.size - 1 ? "border-b border-slate-100" : "" }
          .w-32
            %p.text-xs.font-medium.uppercase.tracking-wider.text-slate-500 Talonario
            %p.text-xl.font-semibold.text-slate-900= note.paper_number
          .flex-1.text-sm.text-slate-600
            = pluralize(note.order_items.size, "ítem")
          .w-32.text-right
            %p.text-xs.font-medium.uppercase.tracking-wider.text-slate-500 Total
            %p.text-lg.font-semibold.text-slate-900= number_to_currency(note.total_amount, unit: "$", separator: ",", delimiter: ".")
          = link_to "Cobrar", new_web_sale_note_payment_path(note),
                    class: "px-5 py-2 bg-slate-900 hover:bg-slate-800 text-white text-sm font-medium rounded-xl"
```

- [ ] **Step 2: Verify in browser**

Boot server, sign in as caja, create a pending immediate order in console, hit `/web/sale_notes`, confirm layout matches spec mockup.

---

### Task 16: `Web::SaleNotes::PaymentsController`

**Files:**
- Create: `app/controllers/web/sale_notes/payments_controller.rb`
- Create: `spec/requests/web/sale_notes/payments_spec.rb`

- [ ] **Step 1: Write failing request spec**

`spec/requests/web/sale_notes/payments_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Web::SaleNotes::Payments", type: :request do
  let(:cashier) { create(:user, role: "caja") }
  let(:product) { create(:product, current_stock: 5, price_unit: 100) }
  let!(:note) do
    o = create(:order, :pending, order_type: "immediate", paper_number: "A-2000",
               total_amount: 200, original_total_amount: 200)
    create(:order_item, order: o, product: product, quantity: 2, unit_price: 100, discount_percent: 0)
    o
  end

  before { sign_in cashier }

  describe "GET new" do
    it "renders the cobro form" do
      get "/web/sale_notes/#{note.id}/payment/new"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("A-2000")
    end
  end

  describe "POST create" do
    it "cobra full cash, confirms note" do
      post "/web/sale_notes/#{note.id}/payment", params: {
        discount_percent: "0",
        tenders: { "0" => { payment_method: "cash", amount: "200,00" } }
      }
      expect(response).to redirect_to(web_sale_notes_path)
      expect(note.reload.status).to eq("confirmed")
    end

    it "rejects discount with non-cash tender" do
      post "/web/sale_notes/#{note.id}/payment", params: {
        discount_percent: "5",
        tenders: {
          "0" => { payment_method: "cash", amount: "100,00" },
          "1" => { payment_method: "transfer", amount: "90,00" }
        }
      }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(note.reload.status).to eq("pending")
    end
  end
end
```

- [ ] **Step 2: Run spec — expect failure**

```bash
bundle exec rspec spec/requests/web/sale_notes/payments_spec.rb
```

- [ ] **Step 3: Create controller**

`app/controllers/web/sale_notes/payments_controller.rb`:

```ruby
module Web
  module SaleNotes
    class PaymentsController < ApplicationController
      before_action :set_note

      def new
        authorize @note, :collect?, policy_class: SaleNotePolicy
      end

      def create
        authorize @note, :collect?, policy_class: SaleNotePolicy

        result = Payments::CollectSaleNote.call(
          order:            @note,
          discount_percent: params[:discount_percent].to_i,
          tenders:          parsed_tenders
        )

        if result.success?
          redirect_to web_sale_notes_path, notice: "Nota #{@note.paper_number} cobrada"
        else
          flash.now[:alert] = result.errors.join(", ")
          render :new, status: :unprocessable_entity
        end
      end

      private

      def set_note
        @note = Order.immediate.pending.find(params[:sale_note_id])
      end

      # Tenders arrive as `tenders[0][payment_method]=cash&tenders[0][amount]=1.500,00`.
      # Strip Argentine formatting (1.500,00 → 1500.00) before to_f.
      def parsed_tenders
        rows = params[:tenders]
        return [] if rows.blank?

        rows.to_unsafe_h.values.filter_map do |row|
          raw = row[:amount].to_s.gsub(".", "").tr(",", ".")
          amount = raw.to_f
          next if amount <= 0
          { payment_method: row[:payment_method], amount: amount }
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run spec**

```bash
bundle exec rspec spec/requests/web/sale_notes/payments_spec.rb
```

Expected: pass.

---

### Task 17: Cobro form view

**Files:**
- Create: `app/views/web/sale_notes/payments/new.html.haml`

- [ ] **Step 1: Create view**

```haml
- content_for :page_title, "Cobrar nota #{@note.paper_number}"

.container.mx-auto.px-6.py-6{ data: { controller: "sale-note-payment",
                                       "sale-note-payment-original-total-value": @note.original_total_amount.to_f,
                                       "sale-note-payment-note-id-value": @note.id } }

  .flex.items-baseline.justify-between.mb-6
    %div
      %p.text-xs.font-medium.uppercase.tracking-wider.text-slate-500 Talonario
      %h1.text-3xl.font-semibold.text-slate-900= @note.paper_number
    = link_to "← Volver al listado", web_sale_notes_path, class: "text-sm text-slate-500 hover:text-slate-900"

  - if flash[:alert]
    .bg-red-50.border.border-red-200.text-red-700.text-sm.rounded-xl.px-4.py-3.mb-4= flash[:alert]

  .grid.grid-cols-1.lg:grid-cols-[1fr_360px].gap-5

    -# LEFT
    .space-y-4

      -# Productos read-only
      .bg-white.border.border-slate-200.rounded-2xl.p-5
        .flex.items-baseline.justify-between.mb-3
          %h3.text-sm.font-semibold.text-slate-900 Productos
          %span.text-xs.text-slate-500
            = pluralize(@note.order_items.size, "ítem")
            · Cliente:
            = @note.customer&.name || "Mostrador"
        %table.w-full.text-sm
          %thead
            %tr.text-slate-500.text-left
              %th.py-2.font-medium.border-b.border-slate-100 Producto
              %th.py-2.font-medium.border-b.border-slate-100.text-center Cant
              %th.py-2.font-medium.border-b.border-slate-100.text-right P. Unit
              %th.py-2.font-medium.border-b.border-slate-100.text-right Subtotal
          %tbody.text-slate-900
            - @note.order_items.each do |oi|
              %tr
                %td.py-2= oi.product.name
                %td.py-2.text-center= oi.quantity
                %td.py-2.text-right= number_to_currency(oi.unit_price, unit: "$", separator: ",", delimiter: ".")
                %td.py-2.text-right= number_to_currency(oi.quantity * oi.unit_price, unit: "$", separator: ",", delimiter: ".")

      = form_with url: web_sale_note_payment_path(@note), method: :post, local: true, data: { "sale-note-payment-target": "form" } do |f|

        -# Descuento
        .bg-white.border.border-slate-200.rounded-2xl.p-5
          %h3.text-sm.font-semibold.text-slate-900.mb-1 Descuento
          %p.text-xs.text-slate-500.mb-3{ data: { "sale-note-payment-target": "discountHelper" } }
            Habilitado solo si la totalidad se paga en efectivo
          = select_tag :discount_percent,
              options_for_select([["0%", 0], ["5%", 5], ["10%", 10]], 0),
              data: { "sale-note-payment-target": "discountSelect",
                      action: "change->sale-note-payment#recalc" },
              class: "w-32 px-3 py-2 border border-slate-300 rounded-xl text-sm bg-white"

        -# Detalle de pago
        .bg-white.border.border-slate-200.rounded-2xl.p-5
          .flex.items-baseline.justify-between.mb-3
            %h3.text-sm.font-semibold.text-slate-900 Detalle de pago
            %span.text-xs.font-medium.text-slate-700.bg-slate-100.px-2.py-0.5.rounded Requerido

          .space-y-2{ data: { "sale-note-payment-target": "tenderRows" } }
            .flex.gap-2.items-center{ data: { "sale-note-payment-target": "tenderRow" } }
              = select_tag "tenders[0][payment_method]",
                  options_for_select([["Efectivo", "cash"], ["Transferencia", "transfer"], ["Cheque", "check"], ["Tarjeta", "card"]], "cash"),
                  data: { "sale-note-payment-target": "tenderMethod",
                          action: "change->sale-note-payment#recalc" },
                  class: "flex-1 px-3 py-2 border border-slate-300 rounded-xl text-sm"
              = text_field_tag "tenders[0][amount]", nil,
                  placeholder: "0,00",
                  data: { "sale-note-payment-target": "tenderAmount",
                          controller: "currency-input",
                          action: "blur->currency-input#format focus->currency-input#unformat input->sale-note-payment#recalc" },
                  class: "w-32 px-3 py-2 border border-slate-300 rounded-xl text-sm text-right"
              %button{ type: "button",
                       data: { action: "click->sale-note-payment#removeTender" },
                       class: "text-slate-400 hover:text-red-500 text-lg px-1" } ×

          %button{ type: "button",
                   data: { action: "click->sale-note-payment#addTender" },
                   class: "mt-3 w-full text-xs text-slate-600 hover:text-slate-900 border border-dashed border-slate-300 rounded-xl py-2" }
            + Agregar método

    -# RIGHT — sticky summary + actions
    .bg-white.border.border-slate-200.rounded-2xl.p-5.h-fit.lg:sticky.lg:top-6

      %h3.text-sm.font-semibold.text-slate-900.mb-3 Resumen

      .space-y-2.text-sm
        .flex.justify-between.text-slate-600
          %span Subtotal
          %span= number_to_currency(@note.original_total_amount, unit: "$", separator: ",", delimiter: ".")
        .flex.justify-between.text-slate-600
          %span Descuento
          %span{ data: { "sale-note-payment-target": "summaryDiscount" } } −$ 0,00
        .border-t.border-slate-200.my-2
        .flex.justify-between.font-semibold.text-slate-900
          %span Total a cobrar
          %span{ data: { "sale-note-payment-target": "summaryTotal" } }= number_to_currency(@note.original_total_amount, unit: "$", separator: ",", delimiter: ".")
        .border-t.border-slate-200.my-2
        .flex.justify-between.text-slate-600
          %span Suma de pagos
          %span{ data: { "sale-note-payment-target": "summaryPaid" } } $ 0,00
        .flex.justify-between.font-medium{ data: { "sale-note-payment-target": "summaryDiff" } }
          %span Diferencia
          %span= number_to_currency(@note.original_total_amount, unit: "$", separator: ",", delimiter: ".")

      %button{ type: "submit",
               form: f.object_id.to_s,
               data: { "sale-note-payment-target": "submitButton" },
               class: "mt-5 w-full bg-slate-900 hover:bg-slate-800 text-white py-2.5 rounded-xl text-sm font-medium" }
        Confirmar cobro

      = button_to "Cancelar nota",
                  cancel_web_sale_note_path(@note),
                  method: :post,
                  data: { confirm: "¿Cancelar la nota #{@note.paper_number}? Esta acción no se puede deshacer." },
                  class: "mt-2 w-full bg-white border border-slate-200 text-slate-600 hover:text-slate-900 py-2 rounded-xl text-sm"
```

> NOTE on the submit button: the previous block uses `form: f.object_id.to_s` to keep the submit button outside the form element. If the layout breaks, move the entire summary card **inside** the form_with block.

- [ ] **Step 2: Verify renders**

Boot server, sign in as caja, visit `/web/sale_notes/<note_id>/payment/new`. Confirm it renders.

---

### Task 18: Stimulus controller `sale_note_payment_controller.js`

**Files:**
- Create: `app/javascript/controllers/sale_note_payment_controller.js`

- [ ] **Step 1: Create controller**

```javascript
import { Controller } from "@hotwired/stimulus"

// Drives the cashier cobro form:
//   - keeps the live summary in sync with discount + tenders
//   - enforces "discount only if 100% cash" rule on the front (back also enforces)
export default class extends Controller {
  static targets = [
    "discountSelect", "discountHelper",
    "tenderRows", "tenderRow", "tenderMethod", "tenderAmount",
    "summaryDiscount", "summaryTotal", "summaryPaid", "summaryDiff",
    "submitButton"
  ]

  static values = {
    originalTotal: Number,
    noteId: Number
  }

  connect() {
    this._tenderIdx = this.tenderRowTargets.length
    this.recalc()
  }

  recalc() {
    const discount = parseInt(this.discountSelectTarget.value, 10) || 0
    const newTotal = +(this.originalTotalValue * (1 - discount / 100)).toFixed(2)

    const tenders = this.#readTenders()
    const allCash = tenders.length > 0 && tenders.every(t => t.method === "cash")
    const paidSum = tenders.reduce((s, t) => s + t.amount, 0)
    const cashOnlyOk = allCash && Math.abs(paidSum - newTotal) < 0.01

    // Enforce cash-only rule on discount
    if (discount > 0 && !cashOnlyOk) {
      this.discountSelectTarget.value = "0"
      this.discountHelperTarget.classList.add("text-red-600")
      return this.recalc()
    } else {
      this.discountHelperTarget.classList.remove("text-red-600")
    }

    const finalTotal = +(this.originalTotalValue * (1 - (parseInt(this.discountSelectTarget.value, 10) || 0) / 100)).toFixed(2)
    const finalPaid  = paidSum
    const diff       = +(finalTotal - finalPaid).toFixed(2)

    this.summaryDiscountTarget.textContent = `−${this.#fmt(this.originalTotalValue - finalTotal)}`
    this.summaryTotalTarget.textContent    = this.#fmt(finalTotal)
    this.summaryPaidTarget.textContent     = this.#fmt(finalPaid)
    this.summaryDiffTarget.textContent     = this.#fmt(diff)
    this.summaryDiffTarget.classList.toggle("text-emerald-600", Math.abs(diff) < 0.01)
    this.submitButtonTarget.disabled       = Math.abs(diff) >= 0.01
    this.submitButtonTarget.classList.toggle("opacity-50", this.submitButtonTarget.disabled)
  }

  addTender(event) {
    event.preventDefault()
    const idx = this._tenderIdx++
    const row = this.tenderRowTargets[0].cloneNode(true)
    // rename input names to keep params unique
    row.querySelector("select").name = `tenders[${idx}][payment_method]`
    const input = row.querySelector("input")
    input.name  = `tenders[${idx}][amount]`
    input.value = ""
    this.tenderRowsTarget.appendChild(row)
    this.recalc()
  }

  removeTender(event) {
    event.preventDefault()
    if (this.tenderRowTargets.length <= 1) return
    event.currentTarget.closest("[data-sale-note-payment-target='tenderRow']").remove()
    this.recalc()
  }

  #readTenders() {
    return this.tenderRowTargets.map(row => {
      const method = row.querySelector("select").value
      const raw    = row.querySelector("input").value.replace(/\./g, "").replace(/,/g, ".")
      const amount = parseFloat(raw) || 0
      return { method, amount }
    })
  }

  #fmt(n) {
    return new Intl.NumberFormat("es-AR", { style: "currency", currency: "ARS", minimumFractionDigits: 2 }).format(n)
  }
}
```

- [ ] **Step 2: Verify Stimulus registers controller automatically**

If the project uses `bin/importmap pin` or auto-registration via `controllers/index.js`, the new controller should be picked up. Run:

```bash
ls app/javascript/controllers/index.js 2>/dev/null && cat app/javascript/controllers/index.js
```

If `index.js` is using `eagerLoadControllersFrom("controllers", application)` no further wiring is needed. Otherwise, register explicitly per existing pattern.

- [ ] **Step 3: Manual browser test**

Boot server. As caja, visit cobro form. Verify:
- Typing in amount updates summary live (currency-input format on blur).
- Setting discount to 5% with full cash matching new total works.
- Adding a transfer tender automatically resets discount to 0% and helper turns red.
- Confirm submit disabled while diff != 0.

---

### Task 19: Sidebar entry

**Files:**
- Modify: `app/views/layouts/web/_sidebar.html.haml`

- [ ] **Step 1: Add inside the `%nav` block**

Insert directly after the "Productos" link and before the "Ventas" dropdown:

```haml
- if policy(Order).index? rescue false
  - pending_notes_count = Order.immediate.pending.count
  = link_to web_sale_notes_path, class: "flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium #{controller_name == 'sale_notes' ? 'text-slate-900 bg-slate-100' : 'text-slate-600 hover:text-slate-900 hover:bg-slate-50 transition-colors'}" do
    %span.text-base 🧾
    %span Notas de pedido
    - if pending_notes_count > 0
      %span.ml-auto.inline-flex.items-center.justify-center.w-5.h-5.rounded-full.bg-amber-100.text-amber-700.text-xs.font-bold= pending_notes_count
```

> Visibility uses `policy(Order)` with `policy_class: SaleNotePolicy` — but `policy()` doesn't accept policy_class. Use a tiny inline check instead:

Replace with:

```haml
- if (current_user&.caja? || current_user&.admin?)
  - pending_notes_count = Order.immediate.pending.count
  = link_to web_sale_notes_path, class: "flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium #{controller_name == 'sale_notes' ? 'text-slate-900 bg-slate-100' : 'text-slate-600 hover:text-slate-900 hover:bg-slate-50 transition-colors'}" do
    %span.text-base 🧾
    %span Notas de pedido
    - if pending_notes_count > 0
      %span.ml-auto.inline-flex.items-center.justify-center.w-5.h-5.rounded-full.bg-amber-100.text-amber-700.text-xs.font-bold= pending_notes_count
```

- [ ] **Step 2: Visual check**

Sign in as `caja` → sidebar shows "Notas de pedido" entry with pending count. Sign in as `vendedor` → entry absent.

---

### Task 20: `OrderPolicy` — `cancel_pending?` for vendor

**Files:**
- Modify: `app/policies/order_policy.rb`

The current `cancel?` is admin-only; we keep that for confirmed orders. For pending orders, allow vendor/caja/admin via `cancel_pending?`. Existing OrdersController calls `@order, :cancel?`. Update the controller branch to use the right method based on state.

- [ ] **Step 1: Add method to policy**

```ruby
def cancel_pending?
  record.pending_status? && (user.vendedor? || user.caja? || user.admin?)
end
```

- [ ] **Step 2: Update `Web::OrdersController#cancel`**

```ruby
def cancel
  policy_method = @order.pending_status? ? :cancel_pending? : :cancel?
  authorize @order, policy_method
  result = Sales::CancelOrder.call(
    order: @order,
    reason: params[:reason] || "Anulada desde interfaz"
  )

  if result.success?
    redirect_to web_orders_path, notice: "Venta anulada"
  else
    redirect_to web_orders_path, alert: result.errors.join(", ")
  end
end
```

(Removed "y stock reintegrado" from flash since stock isn't reverted today.)

- [ ] **Step 3: Add policy spec**

`spec/policies/order_policy_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe OrderPolicy do
  subject { described_class.new(user, order) }

  let(:order) { create(:order, :pending, paper_number: "A-3000", total_amount: 100, original_total_amount: 100) }

  context "vendor on pending order" do
    let(:user) { create(:user, role: "vendedor") }
    it { is_expected.to permit_action(:cancel_pending) }
    it { is_expected.not_to permit_action(:cancel) }
  end

  context "admin on confirmed order" do
    let(:user) { create(:user, role: "admin") }
    before { order.update_column(:status, "confirmed") }
    it { is_expected.to permit_action(:cancel) }
  end
end
```

- [ ] **Step 4: Run spec**

```bash
bundle exec rspec spec/policies/order_policy_spec.rb
```

Expected: pass. If `permit_action` is unavailable, replace with explicit `expect(subject.cancel_pending?).to be true` style.

---

## Phase 5 — Cleanup

### Task 21: Update `WORKING_CONTEXT.md`

**Files:**
- Modify: `WORKING_CONTEXT.md`

- [ ] **Step 1: Apply these edits**

1. **Orders section** — replace the third bullet ("`order_type` enum…") with:

```
* `order_type` enum: `immediate` and `credit`. `status` enum: `pending`, `confirmed`, `cancelled` — orders nacen `pending`; promueven a `confirmed` cuando `outstanding_balance == 0`; `cancelled` por cancelación explícita.
* Created via `Sales::CreateOrder` (from `Web::OrdersController#create`). Solo recibe `customer:, items:, order_type:, paper_number:, channel:, source:, sale_date:`. **No** captura pagos ni descuento — el vendedor genera una nota, caja la cobra después.
* `paper_number` es obligatorio para toda nota (live o from_paper).
* El form `new` muestra solo Cliente · Tipo · Talonario · Productos (sin "Descuento" ni "Detalle de Pago").
* Cancelled via `Sales::CancelOrder` (member cancel). `OrderPolicy#cancel_pending?` permite vendedor/caja/admin sobre notas `pending`; `#cancel?` solo admin sobre `confirmed`.
* **Stock no se modifica al vender hoy** — `Sales::CreateOrder` solo valida disponibilidad; no crea `StockMovement`. `Sales::CancelOrder` sigue restockeando vía `Inventory::AdjustStock` (asimétrico — pre-existing behavior).
* Descuento de inmediatas: se aplica en el cobro de caja vía `Payments::CollectSaleNote`. Cap 0/5/10%, distribuido a todos los items. **Regla:** solo permitido si la totalidad se paga en efectivo.
* Descuento de credit: sin cambios respecto a feat_09 (per-item 0-20% en primer cobro vía `Payments::AllocatePayment`).
```

2. **Customer account payments section** — replace the bullet about `Order#outstanding_balance` with:

```
* `Order#outstanding_balance` = `total_amount − payment_allocations.sum(:amount)` para órdenes no canceladas (de **cualquier** tipo). Promoción automática a `confirmed` cuando llega a 0 vía `Order#refresh_status_from_balance!`, invocado desde `Payments::AllocatePayment` y `Payments::CollectSaleNote` al final de la transacción.
```

Replace the `Customer#current_balance` bullet:

```
* `Customer#current_balance` = `SUM(credit_orders.total_amount) − SUM(payment_allocations on credit orders)` filtrando `status IN ('pending', 'confirmed')`.
```

3. **Web surface — Dashboard** bullet: replace "sum of **confirmed** orders" with "sum of **active** (no canceladas) orders".

4. **Web surface — Customers `debtors`** bullet: no change (uses `with_outstanding_balance` which now correctly includes pending).

5. **Web surface — add new bullet for sale_notes**:

```
* **Sale notes** (caja): index/cancel + nested payment new/create. `Web::SaleNotesController#index` lista `Order.immediate.pending`; cobro vía `Payments::CollectSaleNote` (descuento global 0/5/10, multi-tender, regla cash-only para descuento).
```

6. **Active services** section: add `Payments::CollectSaleNote` under "Payments".

7. **Important gaps** section: remove or update any line that no longer reflects reality.

---

### Task 22: Delete deprecated `Payments::RegisterPayment` if still present

**Files:**
- Possibly delete: `app/services/payments/register_payment.rb`

- [ ] **Step 1: Check existence**

```bash
ls app/services/payments/register_payment.rb 2>/dev/null && grep -rn "Payments::RegisterPayment" app/ spec/
```

- [ ] **Step 2: If file exists and has no callers, delete file + any spec**

```bash
rm app/services/payments/register_payment.rb
rm -f spec/services/payments/register_payment_spec.rb
```

- [ ] **Step 3: Run full suite**

```bash
bundle exec rspec
```

Expected: green.

---

### Task 23: Full suite + lint pass

- [ ] **Step 1: Run full test suite**

```bash
bundle exec rspec
```

Expected: all green. If failures remain, fix at the failure site — do not skip.

- [ ] **Step 2: Lint**

```bash
bundle exec rubocop
```

Run `bundle exec rubocop -a` for auto-fixable issues.

- [ ] **Step 3: Manual end-to-end smoke**

```bash
bin/rails server
```

Walk this happy path in a browser:
1. Sign in as `vendedor` → `/web/orders/new` → create an **immediate** nota (Mostrador, talonario `A-1000`, 1 product) → see "Nota #N creada".
2. Sign in as `caja` → sidebar shows "Notas de pedido (1)" → click → see the row with talonario A-1000 → click "Cobrar".
3. Form: enter 100% cash matching total → "Confirmar cobro" → back at listing, list is empty.
4. Verify the order on `/web/orders/<id>` shows "Confirmada" badge and payment allocations.
5. Repeat with a **credit** nota for a credit customer → goes to `/web/customers/<id>/payments/new` → cobro parcial → order stays `pending`; full cobro → `confirmed`.

Stop server.

---

### Task 24: Final commit message (DO NOT run git yourself)

Present this commit message to the user verbatim. Per user preference, **do not** run `git add` or `git commit` — the user applies the commit manually.

```
feat(feat_10): split sale into vendor note + cashier cobro

Vendor now creates a sale note (cliente + productos + tipo + N° de
talonario) in `pending` status — no payment, no discount captured at
creation. Cashier collects payment on immediate notes from a dedicated
"Notas de pedido" screen with global discount (0/5/10%, cash-only rule)
and multi-tender support. Credit notes flow unchanged through
receivables; `pending` → `confirmed` auto-promotion happens in both
services when `outstanding_balance` reaches zero.

- Order: new `pending` status, generalized `outstanding_balance`,
  `refresh_status_from_balance!` helper, `paper_number` required for
  every order.
- Sales::CreateOrder: drops `payments:` and `discount_percent:`
  parameters; always creates `pending`.
- Payments::AllocatePayment: now accepts pending credit orders and
  promotes them to confirmed on full payment.
- Payments::CollectSaleNote: new service for the cashier flow,
  enforces the cash-only discount rule on backend.
- Web::SaleNotesController + nested PaymentsController, Pundit
  SaleNotePolicy, sidebar entry for caja/admin.
- Customer#current_balance and with_outstanding_balance now include
  `pending` credit orders; dashboard and receivables filters updated
  accordingly.
- Vendor form simplified (drops Descuento + Detalle de Pago cards);
  order_form_controller.js slimmed; cobro form uses currency-input
  pattern.
- WORKING_CONTEXT.md corrected.
```

---

## Self-Review

Spec coverage scan vs `2026-05-27-sale-note-cashier-split-design.md`:

| Spec requirement | Task(s) |
|---|---|
| Order enum + state machine | 1, 2 |
| `outstanding_balance` generalized | 2 |
| `refresh_status_from_balance!` | 2 |
| `paper_number` required for live | 2, 3 (factory) |
| `Sales::CreateOrder` simplification | 4 |
| Vendor form cleanup | 5 |
| `order_form_controller.js` slim down | 6 |
| `Payments::AllocatePayment` accepts pending + promotes | 7 |
| `Customer` scope updates | 8 |
| `DashboardController` scope | 9 |
| Receivables filter | 10 |
| Order index/show badge updates | 11 |
| `Payments::CollectSaleNote` service | 12 |
| Routes | 13 |
| `Web::SaleNotesController` | 14 |
| Listing view | 15 |
| Nested payments controller | 16 |
| Cobro form view | 17 |
| Stimulus | 18 |
| Sidebar entry | 19 |
| Policy (`cancel_pending?`, `SaleNotePolicy`) | 14, 20 |
| `WORKING_CONTEXT.md` cleanup | 21 |
| Deprecated `RegisterPayment` removal | 22 |
| Final smoke + lint | 23 |
| Commit message handoff | 24 |

All covered. No placeholders, no `TBD`, no "add tests" without test code.

---

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-05-27-sale-note-cashier-split.md`. Two execution options:**

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — Execute tasks in this session using `executing-plans`, batch execution with checkpoints.

**Which approach?**
