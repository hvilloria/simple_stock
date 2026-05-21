# feat_08 — Discount on Immediate Sales Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist a global discount (0/5/10%) on immediate sale orders, recompute totals against it, keep the original total as audit data, and surface the breakdown in the new-order form and the show view.

**Architecture:**
- Per-item `discount_percent` on `order_items` (NOT NULL, default 0); `original_total_amount` on `orders` (NOT NULL after backfill).
- Form sends a single global `discount_percent`; controller passes it to `Sales::CreateOrder` which fans it out to every item and recomputes both totals inside the existing transaction.
- View updates: reorder the left column in `orders/new`, add a "Descuento" card, add Subtotal/Descuento rows to the right summary card and to the `orders/show` table footer + right summary.
- Stimulus `order_form_controller` extended to recalculate post-discount total live and hide the card when the order type switches to `credit`.

**Tech Stack:** Rails 7.2, PostgreSQL, RSpec, Hotwire (Stimulus), HAML, TailwindCSS.

**Spec:** `docs/superpowers/specs/2026-05-21-discount-on-immediate-sales-design.md`

**Commit strategy:** This codebase uses a single commit per feature (no intermediate commits). Do **not** commit between tasks — there is a single "Final commit" task at the end.

---

## File Structure

**Create:**
- `db/migrate/<timestamp>_add_discount_to_orders_and_items.rb` — adds `discount_percent` and `original_total_amount`, backfills, enforces NOT NULL.

**Modify:**
- `app/models/order_item.rb` — `discount_percent` validations.
- `app/models/order.rb` — `original_total_amount` validation + `#discount_amount` + `#discount_percent_display`.
- `app/services/sales/create_order.rb` — accept `discount_percent`, propagate to items, recompute totals.
- `app/controllers/web/orders_controller.rb` — read `discount_percent` param, forward to service.
- `app/views/web/orders/new.html.haml` — reorder cards, extract payment block, add "Descuento" card, add summary breakdown.
- `app/javascript/controllers/order_form_controller.js` — new targets + discount handlers.
- `app/views/web/orders/show.html.haml` — add Subtotal/Discount rows to table tfoot and right summary card.
- `spec/models/order_item_spec.rb` — discount validations.
- `spec/models/order_spec.rb` — `original_total_amount` + helpers.
- `spec/services/sales/create_order_spec.rb` — discount scenarios.
- `spec/requests/web/orders_spec.rb` — POST with discount.
- `WORKING_CONTEXT.md` — document the new fields, service param, and form layout change.

---

## Task 1: Migration

**Files:**
- Create: `db/migrate/<timestamp>_add_discount_to_orders_and_items.rb`

- [ ] **Step 1: Generate the migration**

Run: `bin/rails generate migration AddDiscountToOrdersAndItems`

This produces a file under `db/migrate/`. Open it and replace its body with the content in Step 2.

- [ ] **Step 2: Fill in the migration**

```ruby
class AddDiscountToOrdersAndItems < ActiveRecord::Migration[7.2]
  def up
    add_column :order_items, :discount_percent, :decimal, precision: 5, scale: 2, default: 0, null: false
    add_column :orders, :original_total_amount, :decimal, precision: 10, scale: 2

    # Backfill any existing rows (seeds, dev) so original_total_amount mirrors total_amount.
    execute "UPDATE orders SET original_total_amount = total_amount WHERE original_total_amount IS NULL"

    change_column_null :orders, :original_total_amount, false
  end

  def down
    remove_column :orders, :original_total_amount
    remove_column :order_items, :discount_percent
  end
end
```

- [ ] **Step 3: Run the migration**

Run: `bin/rails db:migrate`
Expected: migration runs cleanly; `schema.rb` updates with the two new columns.

- [ ] **Step 4: Reload schema in test DB**

Run: `bin/rails db:test:prepare`
Expected: no output (or schema reload confirmation).

---

## Task 2: `OrderItem` discount validations (TDD)

**Files:**
- Modify: `app/models/order_item.rb`
- Modify: `spec/models/order_item_spec.rb`

- [ ] **Step 1: Add failing specs**

Append to `spec/models/order_item_spec.rb` (inside the existing top-level `describe OrderItem do`):

```ruby
  describe "discount_percent" do
    let(:customer) { Customer.create!(name: "Test", customer_type: "retail") }
    let(:credit_customer) { Customer.create!(name: "Cred", customer_type: "workshop", has_credit_account: true) }
    let(:product) { Product.create!(sku: "X-1", name: "P", price_unit: 100, cost_unit: 50, cost_currency: "ARS") }

    def build_item(order:, percent:)
      OrderItem.new(order: order, product: product, quantity: 1, unit_price: 100, discount_percent: percent)
    end

    let(:immediate_order) do
      Order.create!(customer: customer, order_type: "immediate", source: "live",
                    sale_date: Date.today, total_amount: 100, original_total_amount: 100, status: "confirmed")
    end

    let(:credit_order) do
      Order.create!(customer: credit_customer, order_type: "credit", source: "live",
                    sale_date: Date.today, total_amount: 100, original_total_amount: 100, status: "confirmed")
    end

    it "is invalid with discount_percent < 0" do
      item = build_item(order: immediate_order, percent: -1)
      expect(item).not_to be_valid
      expect(item.errors[:discount_percent]).to be_present
    end

    it "is invalid with discount_percent > 20" do
      item = build_item(order: immediate_order, percent: 25)
      expect(item).not_to be_valid
      expect(item.errors[:discount_percent]).to be_present
    end

    it "is invalid with discount_percent > 10 when order is immediate" do
      item = build_item(order: immediate_order, percent: 15)
      expect(item).not_to be_valid
      expect(item.errors[:discount_percent]).to be_present
    end

    it "is invalid with discount_percent > 0 when order is credit" do
      item = build_item(order: credit_order, percent: 5)
      expect(item).not_to be_valid
      expect(item.errors[:discount_percent]).to be_present
    end

    it "is valid with discount_percent = 10 when order is immediate" do
      item = build_item(order: immediate_order, percent: 10)
      expect(item).to be_valid
    end

    it "is valid with discount_percent = 0 in any order_type" do
      expect(build_item(order: immediate_order, percent: 0)).to be_valid
      expect(build_item(order: credit_order, percent: 0)).to be_valid
    end
  end
```

- [ ] **Step 2: Run the failing specs**

Run: `bundle exec rspec spec/models/order_item_spec.rb -e "discount_percent"`
Expected: all 6 examples FAIL because the validation does not exist yet.

- [ ] **Step 3: Implement the validations**

Replace the body of `app/models/order_item.rb` with:

```ruby
class OrderItem < ApplicationRecord
  belongs_to :order
  belongs_to :product

  validates :quantity, numericality: { greater_than: 0 }
  # unit_price puede ser NULL en modo ventas-lite
  # Si es NULL, se trata como 0 en los cálculos
  validates :unit_price,
            numericality: { greater_than_or_equal_to: 0 },
            allow_nil: true
  validates :discount_percent,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 20 }
  validate :discount_within_order_type_cap

  private

  def discount_within_order_type_cap
    return if order.nil? || discount_percent.nil? || discount_percent.zero?

    if order.credit_order_type?
      errors.add(:discount_percent, "no se permite descuento en ventas a crédito")
    elsif order.immediate_order_type? && discount_percent > 10
      errors.add(:discount_percent, "no puede exceder 10% en ventas inmediatas")
    end
  end
end
```

- [ ] **Step 4: Re-run the specs**

Run: `bundle exec rspec spec/models/order_item_spec.rb -e "discount_percent"`
Expected: 6 examples, 0 failures.

---

## Task 3: `Order` discount validations and helpers (TDD)

**Files:**
- Modify: `app/models/order.rb`
- Modify: `spec/models/order_spec.rb`

- [ ] **Step 1: Add failing specs**

Append to `spec/models/order_spec.rb` (inside the existing top-level `describe Order do`):

```ruby
  describe "original_total_amount" do
    let(:customer) { Customer.create!(name: "T", customer_type: "retail") }

    it "is invalid without original_total_amount" do
      order = Order.new(customer: customer, order_type: "immediate", source: "live",
                        sale_date: Date.today, total_amount: 100, status: "confirmed")
      expect(order).not_to be_valid
      expect(order.errors[:original_total_amount]).to be_present
    end

    it "is invalid when original_total_amount < total_amount" do
      order = Order.new(customer: customer, order_type: "immediate", source: "live",
                        sale_date: Date.today, total_amount: 100, original_total_amount: 50, status: "confirmed")
      expect(order).not_to be_valid
      expect(order.errors[:original_total_amount]).to be_present
    end

    it "is valid when original_total_amount == total_amount" do
      order = Order.new(customer: customer, order_type: "immediate", source: "live",
                        sale_date: Date.today, total_amount: 100, original_total_amount: 100, status: "confirmed")
      expect(order).to be_valid
    end
  end

  describe "#discount_amount" do
    let(:customer) { Customer.create!(name: "T", customer_type: "retail") }

    it "returns original_total_amount - total_amount" do
      order = Order.create!(customer: customer, order_type: "immediate", source: "live",
                            sale_date: Date.today, total_amount: 90, original_total_amount: 100, status: "confirmed")
      expect(order.discount_amount).to eq(10)
    end

    it "returns 0 when no discount was applied" do
      order = Order.create!(customer: customer, order_type: "immediate", source: "live",
                            sale_date: Date.today, total_amount: 100, original_total_amount: 100, status: "confirmed")
      expect(order.discount_amount).to eq(0)
    end
  end

  describe "#discount_percent_display" do
    let(:customer) { Customer.create!(name: "T", customer_type: "retail") }
    let(:product) { Product.create!(sku: "X", name: "P", price_unit: 100, cost_unit: 50, cost_currency: "ARS") }

    it "returns the first item's discount_percent as an integer" do
      order = Order.create!(customer: customer, order_type: "immediate", source: "live",
                            sale_date: Date.today, total_amount: 90, original_total_amount: 100, status: "confirmed")
      order.order_items.create!(product: product, quantity: 1, unit_price: 100, discount_percent: 10)
      expect(order.discount_percent_display).to eq(10)
    end

    it "returns 0 when there are no items" do
      order = Order.create!(customer: customer, order_type: "immediate", source: "live",
                            sale_date: Date.today, total_amount: 100, original_total_amount: 100, status: "confirmed")
      expect(order.discount_percent_display).to eq(0)
    end
  end
```

- [ ] **Step 2: Run the failing specs**

Run: `bundle exec rspec spec/models/order_spec.rb -e "original_total_amount" -e "discount_amount" -e "discount_percent_display"`
Expected: 7 examples FAIL (validation not present, helpers undefined).

- [ ] **Step 3: Add validation and helpers**

Open `app/models/order.rb`. Inside the validations block (right after `validate :credit_order_requires_credit_account`) add:

```ruby
  validates :original_total_amount,
            presence: true,
            numericality: { greater_than_or_equal_to: 0 }
  validate :original_total_at_least_current_total
```

Then add two public helper methods (place them near `#calculate_total!`, before `private`):

```ruby
  def discount_amount
    return 0 if original_total_amount.nil? || total_amount.nil?
    original_total_amount - total_amount
  end

  # Assumes all items share the same discount_percent (true for feat_08 immediate sales).
  # Revisit this helper in feat_09 when credit orders introduce per-item discounts.
  def discount_percent_display
    order_items.first&.discount_percent.to_i
  end
```

Finally add the private validation (next to `credit_order_requires_credit_account`):

```ruby
  def original_total_at_least_current_total
    return if original_total_amount.nil? || total_amount.nil?
    if original_total_amount < total_amount
      errors.add(:original_total_amount, "no puede ser menor al total actual")
    end
  end
```

- [ ] **Step 4: Re-run the specs**

Run: `bundle exec rspec spec/models/order_spec.rb -e "original_total_amount" -e "discount_amount" -e "discount_percent_display"`
Expected: 7 examples, 0 failures.

- [ ] **Step 5: Update existing factory/test usage**

Many existing specs build `Order` objects without `original_total_amount`. Run the full `order_spec.rb` and adjacent specs:

Run: `bundle exec rspec spec/models/order_spec.rb spec/models/order_item_spec.rb spec/models/payment_spec.rb spec/models/payment_allocation_spec.rb`

For every example that now fails because an `Order.create!`/`Order.new` lacks `original_total_amount`, add `original_total_amount: <same value as total_amount>` to the attributes. Do not touch logic — only the attribute list.

Re-run until all 4 files are green.

---

## Task 4: `Sales::CreateOrder` accepts discount (TDD)

**Files:**
- Modify: `app/services/sales/create_order.rb`
- Modify: `spec/services/sales/create_order_spec.rb`

- [ ] **Step 1: Add failing specs**

Append to `spec/services/sales/create_order_spec.rb` (inside the existing top-level describe):

```ruby
  describe "with discount_percent" do
    let(:customer) { Customer.create!(name: "Walk-in", customer_type: "retail") }
    let(:product) do
      Product.create!(sku: "DISC-1", name: "Discountable", price_unit: 100, cost_unit: 40, cost_currency: "ARS")
    end

    before do
      StockLocation.find_or_create_by!(name: "Default")
      StockMovement.create!(product: product, stock_location: StockLocation.first!, quantity: 10, movement_type: "adjustment")
      product.recalculate_current_stock!
    end

    def call_with(discount:, order_type: "immediate", payments: nil)
      payments ||= order_type == "immediate" ? [{ amount: discounted_total(discount), payment_method: "cash" }] : []
      Sales::CreateOrder.call(
        customer: customer,
        items: [{ product_id: product.id, quantity: 2, unit_price: 100 }],
        order_type: order_type,
        source: "live",
        discount_percent: discount,
        payments: payments
      )
    end

    def discounted_total(d)
      (200 * (1 - d.to_f / 100)).round(2)
    end

    it "applies discount_percent to all created order_items" do
      result = call_with(discount: 10)
      expect(result.success?).to be true
      expect(result.record.order_items.map(&:discount_percent).map(&:to_i)).to all(eq(10))
    end

    it "persists original_total_amount = sum(qty * unit_price)" do
      result = call_with(discount: 10)
      expect(result.record.original_total_amount.to_f).to eq(200.0)
    end

    it "persists total_amount = post-discount total" do
      result = call_with(discount: 10)
      expect(result.record.total_amount.to_f).to eq(180.0)
    end

    it "returns failure when order_type=credit and discount_percent > 0" do
      credit_customer = Customer.create!(name: "C", customer_type: "workshop", has_credit_account: true)
      result = Sales::CreateOrder.call(
        customer: credit_customer,
        items: [{ product_id: product.id, quantity: 1, unit_price: 100 }],
        order_type: "credit",
        source: "live",
        discount_percent: 5
      )
      expect(result.success?).to be false
      expect(result.errors.join).to match(/descuento.*cr[eé]dito/i)
    end

    it "returns failure when order_type=immediate and discount_percent > 10" do
      result = call_with(discount: 15)
      expect(result.success?).to be false
      expect(result.errors.join).to match(/10%/)
    end

    it "succeeds with discount_percent = 0 (no behavioral change)" do
      result = call_with(discount: 0)
      expect(result.success?).to be true
      expect(result.record.total_amount.to_f).to eq(200.0)
      expect(result.record.original_total_amount.to_f).to eq(200.0)
    end

    it "rejects payment whose sum does not match the post-discount total" do
      result = Sales::CreateOrder.call(
        customer: customer,
        items: [{ product_id: product.id, quantity: 2, unit_price: 100 }],
        order_type: "immediate",
        source: "live",
        discount_percent: 10,
        payments: [{ amount: 200, payment_method: "cash" }] # would match pre-discount, not post
      )
      expect(result.success?).to be false
      expect(result.errors.join).to match(/suma de los pagos/i)
    end
  end
```

- [ ] **Step 2: Run the failing specs**

Run: `bundle exec rspec spec/services/sales/create_order_spec.rb -e "with discount_percent"`
Expected: 7 examples FAIL (service doesn't know about `discount_percent` yet).

- [ ] **Step 3: Modify the service**

Edit `app/services/sales/create_order.rb` to accept and apply `discount_percent`. Specifically:

**3a.** Update `.call` and `#initialize` signatures to add `discount_percent: 0`. Store it as `@discount_percent = discount_percent.to_d`.

**3b.** In `#validate_params`, before `validate_payments`, add:

```ruby
      validate_discount
```

**3c.** Add the private method:

```ruby
    def validate_discount
      return if @discount_percent.zero?

      if @order_type == "credit"
        raise ValidationError, "No se permite descuento en ventas a crédito"
      end

      if @order_type == "immediate" && @discount_percent > 10
        raise ValidationError, "Descuento máximo permitido en ventas inmediatas: 10%"
      end
    end
```

**3d.** Change `#calculate_total` to return the post-discount total (this is the value compared against payments):

```ruby
    def calculate_total
      @calculate_total ||= begin
        subtotal = original_total
        (subtotal * (1 - @discount_percent / 100)).round(2)
      end
    end

    def original_total
      @original_total ||= @items.sum do |item|
        product = Product.find(item.product_id)
        unit_price = item.unit_price || product.price_unit || 0
        item.quantity * unit_price
      end
    end
```

**3e.** Update `#create_order` to also set `original_total_amount`:

```ruby
    def create_order
      @order = Order.create!(
        customer: @customer,
        order_type: @order_type,
        channel: @channel,
        source: @source,
        sale_date: @sale_date,
        paper_number: @paper_number,
        status: "confirmed",
        total_amount: calculate_total,
        original_total_amount: original_total
      )
    end
```

**3f.** Update `#create_order_items` to set `discount_percent` per item:

```ruby
    def create_order_items
      @items.each do |item|
        product = Product.find(item.product_id)
        final_price = item.unit_price || product.price_unit || 0

        OrderItem.create!(
          order: @order,
          product: product,
          quantity: item.quantity,
          unit_price: final_price,
          discount_percent: @discount_percent
        )
      end
    end
```

- [ ] **Step 4: Re-run the new specs**

Run: `bundle exec rspec spec/services/sales/create_order_spec.rb -e "with discount_percent"`
Expected: 7 examples, 0 failures.

- [ ] **Step 5: Run the full service spec file**

Run: `bundle exec rspec spec/services/sales/create_order_spec.rb spec/services/sales/cancel_order_spec.rb`
Expected: 0 failures. If any earlier example fails because the order it creates now misses `original_total_amount`, the cause is that the service must be the one setting it — verify the service path covers it (it should, via `#create_order`). If a spec builds an order directly with `Order.create!`, add the attribute as in Task 3 Step 5.

---

## Task 5: Controller forwards `discount_percent`

**Files:**
- Modify: `app/controllers/web/orders_controller.rb`

- [ ] **Step 1: Pass param to the service**

In `#create`, extend the `Sales::CreateOrder.call` invocation to include `discount_percent`:

```ruby
      result = Sales::CreateOrder.call(
        customer: find_or_create_customer,
        items: parse_items,
        order_type: params.dig(:order, :order_type) || "immediate",
        channel: params.dig(:order, :channel),
        source: params[:source] || "live",
        sale_date: params[:sale_date],
        paper_number: params[:paper_number],
        payments: parse_payments,
        discount_percent: params[:discount_percent].to_f
      )
```

No new strong-params permit is needed because `discount_percent` is read directly from `params`.

- [ ] **Step 2: Smoke-check it compiles**

Run: `bundle exec rails routes | grep orders` (or any rails command that loads the app)
Expected: no NameError/SyntaxError on boot.

---

## Task 6: Request spec for POST with discount (TDD)

**Files:**
- Modify: `spec/requests/web/orders_spec.rb`

- [ ] **Step 1: Add the request specs**

Open `spec/requests/web/orders_spec.rb` and inside the existing top-level describe append:

```ruby
  describe "POST /web/orders with discount_percent" do
    let(:user) { User.create!(email: "u@example.com", password: "password123", role: "admin") }
    let(:product) do
      Product.create!(sku: "REQ-1", name: "Req", price_unit: 1000, cost_unit: 500, cost_currency: "ARS").tap do |p|
        StockLocation.find_or_create_by!(name: "Default")
        StockMovement.create!(product: p, stock_location: StockLocation.first!, quantity: 5, movement_type: "adjustment")
        p.recalculate_current_stock!
      end
    end

    before { sign_in user }

    def base_params(discount:, order_type: "immediate", payment_amount:)
      {
        order: { order_type: order_type, customer_id: "mostrador", channel: "counter" },
        purchase_items: [{ product_id: product.id.to_s, quantity: "1", unit_price: "1000" }],
        payments: { "0" => { amount: payment_amount.to_s, payment_method: "cash" } },
        source: "live",
        sale_date: Date.today.to_s,
        discount_percent: discount.to_s
      }
    end

    it "creates the order with the post-discount total" do
      post web_orders_path, params: base_params(discount: 10, payment_amount: 900)
      expect(response).to redirect_to(web_orders_path)
      created = Order.order(:id).last
      expect(created.total_amount.to_f).to eq(900.0)
      expect(created.original_total_amount.to_f).to eq(1000.0)
      expect(created.order_items.first.discount_percent.to_i).to eq(10)
    end

    it "re-renders new on discount > 10 for immediate" do
      post web_orders_path, params: base_params(discount: 15, payment_amount: 850)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to match(/10%/)
    end
  end
```

(If the spec file lacks a `sign_in` helper, copy the pattern from existing examples in the same file.)

- [ ] **Step 2: Run the specs**

Run: `bundle exec rspec spec/requests/web/orders_spec.rb -e "discount_percent"`
Expected: 2 examples, 0 failures.

---

## Task 7: Update the `orders/new` form view

**Files:**
- Modify: `app/views/web/orders/new.html.haml`

- [ ] **Step 1: Reorder cards and extract the payment block**

The current grid (`.grid.grid-cols-1.md:grid-cols-2.gap-6`) holds:
- Card 1 (Cliente) — includes the "Detalle de Pago" sub-block.
- Card 2 (Resumen) — sticky right, `md:row-span-2`.
- Card 3 (Productos).

Rebuild the left column so it shows, in this exact order:

1. **Información del Cliente** — same content but **without** the "Detalle de Pago" sub-block (delete the `.border-t.border-gray-200.pt-4{ data: { order_form_target: "paymentSection" } } ... end` and the "+ Agregar método de pago"/`paymentSummary` block).
2. **Productos** (existing card 3, moved up).
3. **Descuento** (new card — see Step 2).
4. **Detalle de Pago** (extracted block — see Step 3).

The Resumen card on the right stays unchanged in position; its `md:row-span-2` should be updated to `md:row-span-4` so it still spans the full height of the left column.

- [ ] **Step 2: Insert the Descuento card**

Place this card between Productos and Detalle de Pago:

```haml
      -# ============ Card "Descuento" (visible solo en venta inmediata) ============
      .bg-white.border.border-slate-200.rounded-lg.p-6{ data: { order_form_target: "discountCard" } }
        %h3.text-lg.font-semibold.text-gray-900.mb-2 Descuento
        .flex.items-center.justify-between.gap-4
          %p.text-xs.text-gray-500 Se aplica al total de la venta. Máx. 10% en ventas inmediatas.
          = select_tag :discount_percent,
              options_for_select([["0%", 0], ["5%", 5], ["10%", 10]], 0),
              data: { order_form_target: "discountSelect", action: "change->order-form#discountChanged" },
              class: "w-32 px-4 py-2 border border-gray-300 rounded-lg text-sm font-semibold text-center focus:ring-2 focus:ring-gray-700 focus:border-transparent transition-all"
```

- [ ] **Step 3: Insert the Detalle de Pago card**

Move the previously-removed payment block into its own card, **after** the Descuento card:

```haml
      -# ============ Card "Detalle de Pago" ============
      .bg-white.border.border-slate-200.rounded-lg.p-6{ data: { order_form_target: "paymentSection" } }
        .flex.items-center.justify-between.mb-3
          %div
            %h4.text-sm.font-semibold.text-gray-900{ data: { order_form_target: "paymentSectionTitle" } } Detalle de Pago
            %p.text-xs.text-gray-500.mt-0.5{ data: { order_form_target: "paymentSectionSubtitle" } } La suma debe coincidir con el total de la venta
          %span.text-xs.font-semibold.px-2.py-0.5.rounded.bg-red-50.text-red-700{ data: { order_form_target: "paymentSectionBadge" } } Requerido

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

- [ ] **Step 4: Add Subtotal/Descuento rows to the right Resumen card**

In the Resumen card, between the big Total block (`.text-center.mb-6 ...`) and the Items/Cantidad block, insert:

```haml
        -# Desglose descuento (solo visible cuando discount > 0)
        .border-t.border-gray-200.py-4.hidden{ data: { order_form_target: "summaryDiscountRow" } }
          .flex.justify-between.text-sm.mb-2
            %span.text-gray-600 Subtotal
            %span.text-gray-500.line-through{ data: { order_form_target: "summarySubtotal" } } $0
          .flex.justify-between.text-sm
            %span.text-amber-700{ data: { order_form_target: "summaryDiscountLabel" } } Descuento −0%
            %span.font-semibold.text-amber-700{ data: { order_form_target: "summaryDiscount" } } −$0
```

(The existing `summaryBreakdown` block from feat_07 stays as-is — it shows "Cobrás ahora / A cuenta corriente" in credit.)

- [ ] **Step 5: Visual check (manual)**

Start the dev server:

```bash
bin/dev
```

Open `http://localhost:3000/web/orders/new`. Verify the left column order is **Cliente → Productos → Descuento → Detalle de Pago**, the Resumen card is sticky on the right, and the Descuento card matches the spec mockup. Stop the server.

(Stimulus wiring comes in the next task — for now the dropdown won't recalc anything.)

---

## Task 8: Stimulus controller — discount logic

**Files:**
- Modify: `app/javascript/controllers/order_form_controller.js`

- [ ] **Step 1: Register new targets**

In the `static targets = [...]` array, append:

```
"discountSelect", "discountCard", "summaryDiscountRow", "summarySubtotal", "summaryDiscount", "summaryDiscountLabel"
```

- [ ] **Step 2: Read the discount in `calculateTotal()`**

Replace `calculateTotal()` with:

```javascript
  discountPercent() {
    if (!this.hasDiscountSelectTarget) return 0
    return parseFloat(this.discountSelectTarget.value) || 0
  }

  calculateSubtotal() {
    return this.items.reduce((sum, item) => sum + (item.price_unit * item.quantity), 0)
  }

  calculateTotal() {
    const subtotal = this.calculateSubtotal()
    const d = this.discountPercent()
    return Math.round(subtotal * (1 - d / 100) * 100) / 100
  }
```

This makes the existing `updateSummary()` and `updatePaymentTotal()` automatically reflect the post-discount total — they already call `calculateTotal()`.

- [ ] **Step 3: Add `discountChanged()` to refresh the breakdown**

Append this method on the controller class (after `updateSummary`):

```javascript
  discountChanged() {
    this.refreshDiscountBreakdown()
    this.updateSummary()
  }

  refreshDiscountBreakdown() {
    if (!this.hasSummaryDiscountRowTarget) return

    const subtotal = this.calculateSubtotal()
    const d = this.discountPercent()
    const discountAmount = Math.round(subtotal * d) / 100

    if (d > 0) {
      this.summaryDiscountRowTarget.classList.remove("hidden")
      if (this.hasSummarySubtotalTarget) {
        this.summarySubtotalTarget.textContent = `$${this.formatCurrency(subtotal)}`
      }
      if (this.hasSummaryDiscountLabelTarget) {
        this.summaryDiscountLabelTarget.textContent = `Descuento −${d}%`
      }
      if (this.hasSummaryDiscountTarget) {
        this.summaryDiscountTarget.textContent = `−$${this.formatCurrency(discountAmount)}`
      }
    } else {
      this.summaryDiscountRowTarget.classList.add("hidden")
    }
  }
```

- [ ] **Step 4: Hide/reset the discount card when order_type changes**

Extend `applyPaymentMode(orderType)` — at the end of the method, add:

```javascript
    if (this.hasDiscountCardTarget) {
      if (orderType === "credit") {
        if (this.hasDiscountSelectTarget) this.discountSelectTarget.value = "0"
        this.discountCardTarget.classList.add("hidden")
      } else {
        this.discountCardTarget.classList.remove("hidden")
      }
      this.refreshDiscountBreakdown()
    }
```

- [ ] **Step 5: Keep the breakdown in sync after item changes**

`updateSummary()` already runs whenever items change (add/remove/qty/price). Add one line at the start of `updateSummary()`:

```javascript
    this.refreshDiscountBreakdown()
```

- [ ] **Step 6: Call `refreshDiscountBreakdown()` on connect**

In `connect()`, after `this.updateSummary()`, add:

```javascript
    this.refreshDiscountBreakdown()
```

- [ ] **Step 7: Manual smoke test**

Start `bin/dev`. Open `http://localhost:3000/web/orders/new`. Then:

1. Add two products totalling $25.000. Total reads $25.000.
2. Select discount 10%. Total reads $22.500; right column shows "Subtotal $25.000" (line-through) and "Descuento −10% −$2.500".
3. Type $22.500 in the payment row. Submit button enables; status is "✓ Coincide con el total".
4. Switch to "Cuenta Corriente" (with a credit-enabled customer). The Descuento card disappears, breakdown hides, payment block switches to "Cobro al Momento — Opcional".
5. Switch back to "Contado". Card reappears, discount resets to 0%, breakdown stays hidden until you pick > 0.

If any step fails, fix the controller and re-test. Stop the server.

---

## Task 9: Update `orders/show` view

**Files:**
- Modify: `app/views/web/orders/show.html.haml`

- [ ] **Step 1: Update the Productos Vendidos tfoot**

Find the existing `%tfoot.bg-gray-50` (line ~155) and replace its single row with:

```haml
            %tfoot.bg-gray-50
              - if @order.discount_amount.positive?
                %tr
                  %td.px-6.py-2.text-right.text-sm.text-gray-500{colspan: "5"} Subtotal
                  %td.px-6.py-2.text-right.text-sm.text-gray-500.line-through= currency_ar(@order.original_total_amount)
                %tr
                  %td.px-6.py-2.text-right.text-sm.text-amber-700{colspan: "5"}= "Descuento −#{@order.discount_percent_display}%"
                  %td.px-6.py-2.text-right.text-sm.text-amber-700.font-semibold= "−#{currency_ar(@order.discount_amount)}"
              %tr
                %td.px-6.py-4{colspan: "5"}
                  %span.text-base.font-bold.text-gray-900 Total:
                %td.px-6.py-4.text-right
                  %span.text-xl.font-bold.text-gray-900= currency_ar(@order.total_amount)
```

- [ ] **Step 2: Update the right Resumen card**

Find the block (line ~220) that currently renders Items / Cantidad total / Subtotal. Replace it with:

```haml
        .border-t.border-gray-200.py-4.space-y-3

          .flex.justify-between.text-sm
            %span.text-gray-600 Items
            %span.font-medium.text-gray-900= "#{@order_items.count} productos"

          .flex.justify-between.text-sm
            %span.text-gray-600 Cantidad total
            %span.font-medium.text-gray-900= "#{@order_items.sum(:quantity)} unidades"

          - if @order.discount_amount.positive?
            .flex.justify-between.text-sm
              %span.text-gray-600 Subtotal
              %span.text-gray-500.line-through= currency_ar(@order.original_total_amount)
            .flex.justify-between.text-sm
              %span.text-amber-700= "Descuento −#{@order.discount_percent_display}%"
              %span.font-semibold.text-amber-700= "−#{currency_ar(@order.discount_amount)}"
          - else
            .flex.justify-between.text-sm
              %span.text-gray-600 Subtotal
              %span.font-medium.text-gray-900= currency_ar(@order.total_amount)
```

- [ ] **Step 3: Manual smoke test**

Start `bin/dev`. Create one immediate order with 10% discount via the form. Navigate to the just-created order at `/web/orders/<id>`. Verify:

- Productos table footer shows Subtotal (line-through), Descuento −10% (amber), Total in bold.
- Right Resumen card shows the same Subtotal/Descuento lines in addition to Items/Cantidad.
- The "Total de la Venta" big number equals the post-discount amount.

Then create a second order without discount (0%) and confirm:

- Productos table footer shows only Total.
- Right Resumen card shows Items/Cantidad/Subtotal (no line-through, equal to the total).

Stop the server.

---

## Task 10: Full test suite + RuboCop

**Files:** none

- [ ] **Step 1: Run the full suite**

Run: `bundle exec rspec`
Expected: 0 failures.

If anything is red, the failure is either (a) a model spec missing `original_total_amount` (Task 3 Step 5 protocol — add the attribute to the factory call), or (b) a logic bug introduced earlier. Fix and re-run.

- [ ] **Step 2: Run RuboCop**

Run: `bundle exec rubocop`
Expected: clean, or only pre-existing offences in untouched files.

If there are offences in files we touched, run `bundle exec rubocop -a` for safe auto-fixes; review the diff before continuing.

---

## Task 11: Update `WORKING_CONTEXT.md`

**Files:**
- Modify: `WORKING_CONTEXT.md`

- [ ] **Step 1: Document the new schema and service param**

In the "Orders" section (around the bullet describing `Sales::CreateOrder`), append a paragraph:

```markdown
* **Descuento (immediate):** `Sales::CreateOrder` acepta `discount_percent:` (0–10 en immediate, debe ser 0 en credit). El servicio guarda `orders.original_total_amount` (pre-descuento, NOT NULL) y `order_items.discount_percent` por línea (default 0, NOT NULL, tope superior absoluto 20). `total_amount` queda con el valor post-descuento — toda la lógica downstream (pagos, dashboard, `outstanding_balance`) lee `total_amount` sin cambios. El form `web/orders/new` envía un único `discount_percent` global; el servicio lo reparte a cada item.
```

In the "Web surface" section's bullet for **Orders**, replace the line about the new-sale form with:

```markdown
* **Orders**: index/show/new/create; member **POST `cancel`** → `Sales::CancelOrder`. Create builds items from **`purchase_items`** params y resolves customer via **`Customer.mostrador`** when `customer_id` is blank or `"mostrador"`. El form `new` se ordena en columna izquierda como **Cliente → Productos → Descuento → Detalle de Pago**; el card "Descuento" se oculta cuando `order_type = credit`.
```

(Wording must match the rest of the document; keep it concise.)

---

## Task 12: Final commit

**Files:** none

- [ ] **Step 1: Stage the changes**

Run: `git status` to confirm what changed. You should see:

```
modified: app/controllers/web/orders_controller.rb
modified: app/javascript/controllers/order_form_controller.js
modified: app/models/order.rb
modified: app/models/order_item.rb
modified: app/services/sales/create_order.rb
modified: app/views/web/orders/new.html.haml
modified: app/views/web/orders/show.html.haml
modified: WORKING_CONTEXT.md
modified: db/schema.rb
new file:   db/migrate/<timestamp>_add_discount_to_orders_and_items.rb
modified: spec/models/order_item_spec.rb
modified: spec/models/order_spec.rb
modified: spec/services/sales/create_order_spec.rb
modified: spec/requests/web/orders_spec.rb
```

Stage only those files (no `-A`):

```bash
git add app/controllers/web/orders_controller.rb \
        app/javascript/controllers/order_form_controller.js \
        app/models/order.rb app/models/order_item.rb \
        app/services/sales/create_order.rb \
        app/views/web/orders/new.html.haml \
        app/views/web/orders/show.html.haml \
        WORKING_CONTEXT.md db/schema.rb \
        db/migrate/*add_discount_to_orders_and_items.rb \
        spec/models/order_item_spec.rb spec/models/order_spec.rb \
        spec/services/sales/create_order_spec.rb \
        spec/requests/web/orders_spec.rb \
        docs/superpowers/specs/2026-05-21-discount-on-immediate-sales-design.md \
        docs/superpowers/plans/2026-05-21-discount-on-immediate-sales.md
```

- [ ] **Step 2: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(feat_08): discount on immediate sales

Persist a 0/5/10% discount on immediate orders: discount_percent per
order_item plus original_total_amount on orders (audit). The new-order
form gets a Descuento card, reorders the left column to follow the
operator's flow, and surfaces the breakdown in both the live summary
and the show view. Hidden + reset on credit orders (deferred to feat_09).
EOF
)"
```

- [ ] **Step 3: Verify**

Run: `git status`
Expected: working tree clean (no staged or unstaged changes).

Run: `git log -1`
Expected: the new commit on top of `feat_07-payment-method-on-all-sales`.

---

## Self-review

- All spec sections (schema, model validations, service, form, show, controller, request specs, WORKING_CONTEXT) map to tasks 1–11.
- No placeholders: every step contains complete code or a concrete command with expected output.
- Type consistency: `discount_percent` (decimal, NOT NULL), `original_total_amount` (decimal, NOT NULL after backfill), `Sales::CreateOrder.call(... discount_percent:)`, controller passes `params[:discount_percent].to_f`, Stimulus reads `discountSelectTarget.value`. Names match across tasks.
- TDD: Tasks 2, 3, 4, and 6 follow red → implement → green.
- Single commit at the end per project convention.
