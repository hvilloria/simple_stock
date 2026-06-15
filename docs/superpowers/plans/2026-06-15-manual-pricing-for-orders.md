# Manual Pricing for Orders Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the vendor type the unit price manually when creating a sale note, and write that price back to the product's catalog price for future sales.

**Architecture:** The unit-price field in the order form becomes an editable input (rendered by the existing Stimulus `renderItems` template). `Sales::CreateOrder` gains a `unit_price > 0` validation for every item and, within its existing transaction, updates each product's `price_unit` with the entered value. Price is computed/edited purely client-side; it persists only on submit.

**Tech Stack:** Rails 7.2, Stimulus (Hotwire), HAML, RSpec.

**Commit convention:** This project uses a SINGLE commit per feature. Do NOT commit between tasks. All commits are deferred to the final task.

---

### Task 1: Backend — reject `unit_price <= 0`

**Files:**
- Modify: `app/services/sales/create_order.rb` (method `validate_params`)
- Test: `spec/services/sales/create_order_spec.rb`

- [ ] **Step 1: Write the failing test**

Add inside the top-level `describe '.call'` block in `spec/services/sales/create_order_spec.rb` (e.g. after the existing `context 'with multiple items'` block):

```ruby
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
    end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/sales/create_order_spec.rb -e "with manual pricing rules"`
Expected: FAIL — both examples currently succeed (the service tolerates 0/nil), so `result.success?` is `true`.

- [ ] **Step 3: Write minimal implementation**

In `app/services/sales/create_order.rb`, inside `validate_params`, extend the existing per-item loop that checks `product_id` and `quantity`. Replace this block:

```ruby
      @items.each do |item|
        raise ValidationError, "Product ID is required" unless item.product_id
        raise ValidationError, "Quantity must be greater than zero" unless item.quantity.to_i > 0
      end
```

with:

```ruby
      @items.each do |item|
        raise ValidationError, "Product ID is required" unless item.product_id
        raise ValidationError, "Quantity must be greater than zero" unless item.quantity.to_i > 0
        raise ValidationError, "El precio debe ser mayor a cero" unless item.unit_price.to_f > 0
      end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/sales/create_order_spec.rb -e "with manual pricing rules"`
Expected: PASS (2 examples).

---

### Task 2: Backend — write entered price back to the product

**Files:**
- Modify: `app/services/sales/create_order.rb` (method `create_order_items`)
- Test: `spec/services/sales/create_order_spec.rb`

- [ ] **Step 1: Write the failing test**

Add to the `context 'with manual pricing rules'` block created in Task 1:

```ruby
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/sales/create_order_spec.rb -e "writes the entered price back"`
Expected: FAIL — `product.reload.price_unit` is still `100`, not `175`.

- [ ] **Step 3: Write minimal implementation**

In `app/services/sales/create_order.rb`, update `create_order_items` to write the price back after creating each item. Replace:

```ruby
    def create_order_items
      @items.each do |item|
        product     = Product.find(item.product_id)
        final_price = item.unit_price || product.price_unit || 0

        OrderItem.create!(
          order:            @order,
          product:          product,
          quantity:         item.quantity,
          unit_price:       final_price,
          discount_percent: 0,
          delivered_at:     (@delivered_product_ids.include?(product.id) ? Time.current : nil)
        )
      end
    end
```

with:

```ruby
    def create_order_items
      @items.each do |item|
        product     = Product.find(item.product_id)
        final_price = item.unit_price || product.price_unit || 0

        OrderItem.create!(
          order:            @order,
          product:          product,
          quantity:         item.quantity,
          unit_price:       final_price,
          discount_percent: 0,
          delivered_at:     (@delivered_product_ids.include?(product.id) ? Time.current : nil)
        )

        product.update!(price_unit: final_price)
      end
    end
```

(`validate_params` guarantees `final_price > 0`, so the catalog is never overwritten with 0. `price_unit` is not a protected column like `current_stock`/`cost_unit`, so a direct update is correct.)

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/sales/create_order_spec.rb -e "with manual pricing rules"`
Expected: PASS (4 examples total in this context).

---

### Task 3: Fix existing `from_paper` specs that relied on 0/nil price

The new validation rejects `unit_price <= 0` for all sources. Three existing examples in `context 'with from_paper source'` use `unit_price: 0`/`nil` incidentally and must be updated. The "allows total_amount = 0" and "allows nil unit_price" examples test behavior that no longer exists and are replaced by Task 1's rejection tests.

**Files:**
- Modify: `spec/services/sales/create_order_spec.rb` (`context 'with from_paper source'`)

- [ ] **Step 1: Update the `from_paper` examples**

In `spec/services/sales/create_order_spec.rb`, within `context 'with from_paper source'`:

1. In `it 'creates order with source from_paper'`, change `unit_price: 0` to `unit_price: 100`.

2. Delete the entire `it 'allows total_amount = 0'` example (a zero total is no longer reachable now that price must be > 0).

3. Replace the `it 'allows nil unit_price (uses product price or 0)'` example with:

```ruby
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
```

4. In `it 'skips stock validation (allows selling with zero stock)'`, change `unit_price: 0` to `unit_price: 100` (the example tests stock, not price).

- [ ] **Step 2: Run the full service spec**

Run: `bundle exec rspec spec/services/sales/create_order_spec.rb`
Expected: PASS (all examples green).

- [ ] **Step 3: Sweep for any other caller passing a non-positive price**

Run: `grep -rn "unit_price: 0\b\|unit_price: nil" spec/`
Expected: no matches inside `Sales::CreateOrder.call(...)` argument lists. If any remain in a `CreateOrder` call, change them to a positive price (e.g. `100`). Then run `bundle exec rspec spec/services/sales spec/requests/web/orders_spec.rb` and confirm green.

---

### Task 4: Frontend — editable unit-price input

The price field is rendered by the Stimulus controller's `renderItems` template (not the HAML view), so all changes are in the JS controller. Today the price is a read-only `<p>`; it becomes a number input wired to a new `updatePrice` handler, and the submit button is disabled while any price is `<= 0`.

**Files:**
- Modify: `app/javascript/controllers/order_form_controller.js`

- [ ] **Step 1: Make the price an editable input in `renderItems`**

In `renderItems`, replace this block:

```javascript
          <div class="text-right">
            <p class="text-xs text-gray-500">Precio Unit.</p>
            <p class="w-28 px-2 py-1.5 text-right font-semibold text-gray-900">$${this.formatInputValue(item.price_unit)}</p>
          </div>
```

with:

```javascript
          <div class="text-right">
            <p class="text-xs text-gray-500">Precio Unit.</p>
            <input
              type="number"
              value="${item.price_unit}"
              min="0.01"
              step="0.01"
              data-index="${index}"
              data-action="input->order-form#updatePrice"
              class="w-28 px-2 py-1.5 border border-gray-300 rounded-lg text-right font-semibold"
            />
          </div>
```

- [ ] **Step 2: Add the `updatePrice` handler**

In `app/javascript/controllers/order_form_controller.js`, add this method directly after `updateQuantity`:

```javascript
  updatePrice(event) {
    const index = parseInt(event.currentTarget.dataset.index)
    const newPrice = parseFloat(event.currentTarget.value)

    this.items[index].price_unit = isNaN(newPrice) ? 0 : newPrice
    this.updateItemSubtotal(index)
    this.updateSummary()
  }
```

- [ ] **Step 3: Disable submit while any price is non-positive**

In `updateSubmitButton`, replace:

```javascript
    const disabled = this.items.length === 0 || !customerValid || !paperNumberValid
```

with:

```javascript
    const allPricesValid = this.items.every(item => item.price_unit > 0)

    const disabled = this.items.length === 0 || !customerValid || !paperNumberValid || !allPricesValid
```

- [ ] **Step 4: Manual verification**

Run the app and open `/web/orders/new`. Verify:
- Adding a product shows the price prefilled from the catalog in an editable number input.
- Editing the price updates the line subtotal and the total in the summary in real time.
- Setting a price to 0 (or clearing it) disables the "Crear nota de pedido" button; a positive price re-enables it (with customer + paper_number present).
- Submitting creates the order at the typed price and the product's catalog price (`price_unit`) is updated to the typed value.

---

### Task 5: Verify and commit

**Files:** all of the above.

- [ ] **Step 1: Run the full suite**

Run: `bundle exec rspec`
Expected: all green.

- [ ] **Step 2: Lint**

Run: `bundle exec rubocop`
Expected: no offenses (run `bundle exec rubocop -a` to auto-fix if needed).

- [ ] **Step 3: Single feature commit**

```bash
git add app/services/sales/create_order.rb \
        app/javascript/controllers/order_form_controller.js \
        spec/services/sales/create_order_spec.rb \
        docs/superpowers/specs/2026-06-15-manual-pricing-for-orders-design.md \
        docs/superpowers/plans/2026-06-15-manual-pricing-for-orders.md
git commit -m "feat(feat_12): manual pricing on orders with catalog write-back"
```
