# feat_09 — Discount on Credit Sales Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow operators to apply per-product discounts (0-20%) on credit orders at first payment time; discount freezes once any allocation lands on the order.

**Architecture:** Reuse `order_items.discount_percent` (feat_08 column) — lift the credit-only block, keep the 0-20 numeric cap. Extend `Payments::AllocatePayment` to optionally receive `item_discounts` per allocation; on the first allocation for an order, validate, persist per-item discount, and recalculate `order.total_amount`. UI replaces the orders table on the cobro screen with one card per order that expands on tick, exposing a per-product `% desc` select. No new migrations, no new services.

**Tech Stack:** Rails 7.2, RSpec, HAML, Stimulus (Hotwire), Tailwind. Spec: `docs/superpowers/specs/2026-05-21-discount-on-credit-sales-design.md`.

**Commit policy (project-specific):** no intermediate commits. The user commits once at the end of the feature using the message produced in Task 7. Subagent implementers MUST NOT run `git add` or `git commit` themselves.

---

## File Map

- Modify `app/models/order_item.rb` — relax credit-only block; keep 20% cap.
- Modify `spec/models/order_item_spec.rb` — update the credit-restriction test.
- Modify `app/services/payments/allocate_payment.rb` — accept `item_discounts`, apply on first cobro, recalculate `order.total_amount`.
- Modify `spec/services/payments/allocate_payment_spec.rb` — new context for discount application.
- Modify `app/controllers/web/customers/payments_controller.rb` — parse `discounts` hash into `item_discounts`.
- Modify `app/views/web/customers/payments/new.html.haml` — replace table with cards layout.
- Modify `app/javascript/controllers/payment_allocation_controller.js` — discount recalc, expand-on-tick, locked state.
- Modify `spec/requests/web/customers/payments_spec.rb` — request-level integration for discount flow.
- Modify `WORKING_CONTEXT.md` — document the new behavior.

---

### Task 1: OrderItem — lift the credit-only discount block

**Files:**
- Modify: `app/models/order_item.rb`
- Test: `spec/models/order_item_spec.rb`

- [ ] **Step 1: Replace the obsolete credit-restriction test**

Open `spec/models/order_item_spec.rb`. Replace the example currently labeled `"is invalid with discount_percent > 0 when order is credit"` (around lines 70-74) with two new examples that codify the new rule:

```ruby
    it "is valid with discount_percent = 20 when order is credit" do
      item = build_item(order: credit_order, percent: 20)
      expect(item).to be_valid
    end

    it "is invalid with discount_percent > 20 when order is credit" do
      item = build_item(order: credit_order, percent: 21)
      expect(item).not_to be_valid
      expect(item.errors[:discount_percent]).to be_present
    end
```

Leave every other example in the file untouched. In particular keep `"is invalid with discount_percent > 10 when order is immediate"` (immediate cap stays at 10).

- [ ] **Step 2: Run the failing tests**

Run: `bundle exec rspec spec/models/order_item_spec.rb -e "discount_percent"`
Expected: the new "is valid with discount_percent = 20 when order is credit" example FAILS with an `discount_percent` error message about "no se permite descuento en ventas a crédito".

- [ ] **Step 3: Update the validation in `app/models/order_item.rb`**

Replace the `discount_within_order_type_cap` method body (lines 17-25) so that only the immediate cap remains:

```ruby
  def discount_within_order_type_cap
    return if order.nil? || discount_percent.nil? || discount_percent.zero?

    if order.immediate_order_type? && discount_percent > 10
      errors.add(:discount_percent, "no puede exceder 10% en ventas inmediatas")
    end
  end
```

The numeric `0..20` validation on line 11-12 stays untouched and now governs credit orders too.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bundle exec rspec spec/models/order_item_spec.rb`
Expected: all examples PASS.

---

### Task 2: AllocatePayment — accept and apply `item_discounts`

**Files:**
- Modify: `app/services/payments/allocate_payment.rb`
- Test: `spec/services/payments/allocate_payment_spec.rb`

- [ ] **Step 1: Add the failing happy-path test**

Append to `spec/services/payments/allocate_payment_spec.rb`, inside the top-level `describe ".call"`, after the existing contexts:

```ruby
    context "with item_discounts on the first cobro of an order" do
      let(:multi_item_order) do
        Sales::CreateOrder.call(
          customer: customer,
          items: [
            { product_id: product.id, quantity: 2, unit_price: 100 },
            { product_id: product.id, quantity: 1, unit_price: 100 }
          ],
          order_type: "credit"
        ).record
      end

      it "applies the per-item discounts, recalculates total_amount, and creates the allocation" do
        items = multi_item_order.order_items.order(:id).to_a
        result = described_class.call(
          customer: customer,
          payment_date: Date.today,
          allocations: [
            {
              order_id: multi_item_order.id,
              amount: 280,
              payment_method: "cash",
              item_discounts: { items.first.id => 10, items.last.id => 20 }
            }
          ]
        )

        expect(result.success?).to be true
        multi_item_order.reload
        expect(multi_item_order.original_total_amount.to_f).to eq(300.0)
        expect(multi_item_order.total_amount.to_f).to eq(260.0)
        items.each(&:reload)
        expect(items.first.discount_percent.to_i).to eq(10)
        expect(items.last.discount_percent.to_i).to eq(20)
        expect(multi_item_order.payment_allocations.sum(:amount).to_f).to eq(280.0)
      end

      it "ignores item_discounts when the order already has an allocation (locked)" do
        items = multi_item_order.order_items.order(:id).to_a

        described_class.call(
          customer: customer,
          payment_date: Date.today,
          allocations: [
            {
              order_id: multi_item_order.id,
              amount: 50,
              payment_method: "cash",
              item_discounts: { items.first.id => 10, items.last.id => 0 }
            }
          ]
        )

        multi_item_order.reload
        locked_total = multi_item_order.total_amount.to_f

        result = described_class.call(
          customer: customer,
          payment_date: Date.today,
          allocations: [
            {
              order_id: multi_item_order.id,
              amount: 30,
              payment_method: "cash",
              item_discounts: { items.first.id => 20, items.last.id => 20 }
            }
          ]
        )

        expect(result.success?).to be true
        multi_item_order.reload
        items.each(&:reload)
        expect(multi_item_order.total_amount.to_f).to eq(locked_total)
        expect(items.first.discount_percent.to_i).to eq(10)
        expect(items.last.discount_percent.to_i).to eq(0)
      end

      it "fails when a percent is outside 0..20" do
        items = multi_item_order.order_items.order(:id).to_a
        result = described_class.call(
          customer: customer,
          payment_date: Date.today,
          allocations: [
            {
              order_id: multi_item_order.id,
              amount: 100,
              payment_method: "cash",
              item_discounts: { items.first.id => 25 }
            }
          ]
        )
        expect(result.failure?).to be true
        expect(result.errors.join).to match(/0-20/)
      end

      it "ignores item_discounts entries referencing items that do not belong to the order" do
        items = multi_item_order.order_items.order(:id).to_a
        other_order = Sales::CreateOrder.call(
          customer: customer,
          items: [ { product_id: product.id, quantity: 1, unit_price: 100 } ],
          order_type: "credit"
        ).record
        foreign_item_id = other_order.order_items.first.id

        result = described_class.call(
          customer: customer,
          payment_date: Date.today,
          allocations: [
            {
              order_id: multi_item_order.id,
              amount: 290,
              payment_method: "cash",
              item_discounts: { items.first.id => 10, foreign_item_id => 20 }
            }
          ]
        )

        expect(result.success?).to be true
        multi_item_order.reload
        items.each(&:reload)
        expect(items.first.discount_percent.to_i).to eq(10)
        expect(items.last.discount_percent.to_i).to eq(0)
      end
    end
```

- [ ] **Step 2: Run the failing tests**

Run: `bundle exec rspec spec/services/payments/allocate_payment_spec.rb -e "item_discounts"`
Expected: all four new examples FAIL — either with discounts not applied, or with a NoMethodError if `item_discounts` is treated as an unexpected key.

- [ ] **Step 3: Extend `Payments::AllocatePayment` to apply discounts**

In `app/services/payments/allocate_payment.rb`, modify the `call` method. The transaction block becomes:

```ruby
    def call
      validate_params

      payments = []
      ActiveRecord::Base.transaction do
        @allocations.each { |row| apply_discounts_for(row) }

        grouped_by_method.each do |method, rows|
          total = rows.sum { |r| r[:amount].to_f }
          payment = Payment.create!(
            customer: @customer,
            amount: total,
            payment_method: method,
            payment_date: @payment_date,
            notes: @notes
          )

          rows.each do |row|
            PaymentAllocation.create!(
              payment: payment,
              order_id: row[:order_id],
              amount: row[:amount].to_f
            )
          end

          payments << payment
        end

        Result.new(success?: true, record: payments, errors: [])
      end
    rescue ValidationError => e
      Result.new(success?: false, record: nil, errors: [ e.message ])
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, record: nil, errors: e.record.errors.full_messages)
    rescue StandardError => e
      Rails.logger.error("Error in Payments::AllocatePayment: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      Result.new(success?: false, record: nil, errors: [ "Error registrando el cobro" ])
    end
```

Then add the new private methods after `grouped_by_method`:

```ruby
    def apply_discounts_for(row)
      raw = row[:item_discounts]
      return if raw.blank?

      order = Order.find(row[:order_id])
      # Discounts are frozen once any allocation has landed on the order.
      return if order.payment_allocations.exists?

      percents_by_item_id = raw.to_h.transform_keys(&:to_i).transform_values { |v| v.to_f }
      valid_item_ids = order.order_items.pluck(:id)

      percents_by_item_id.each_value do |percent|
        if percent < 0 || percent > 20
          raise ValidationError, "Descuento fuera de rango (0-20%)"
        end
      end

      order.order_items.each do |item|
        next unless percents_by_item_id.key?(item.id)
        next unless valid_item_ids.include?(item.id)
        item.update!(discount_percent: percents_by_item_id[item.id])
      end

      new_total = order.order_items.reload.sum do |oi|
        unit = (oi.unit_price || 0).to_f
        unit * oi.quantity * (1 - oi.discount_percent.to_f / 100.0)
      end
      order.update!(total_amount: new_total)
    end
```

Note: `valid_item_ids.include?(item.id)` is redundant here (we are already iterating `order.order_items`) but it documents intent — foreign `order_item_id`s entered in `percents_by_item_id` are simply not matched. Keep the line for clarity.

Also: `validate_params` runs before `apply_discounts_for`, so the `amount > order.outstanding_balance` check there sees the **pre-discount** `total_amount`. Move that specific check inline so it runs after the discount has been applied. Replace the `if amount > order.outstanding_balance` block in `validate_params` (around lines 91-93) with a no-op (delete those three lines), and add a new method `check_outstanding_after_discounts!`:

```ruby
    def check_outstanding_after_discounts!(row)
      order = Order.find(row[:order_id])
      amount = row[:amount].to_f
      if amount > order.outstanding_balance
        raise ValidationError,
              "El monto excede el saldo pendiente de la orden ##{order.id} ($#{order.outstanding_balance})"
      end
    end
```

Call it inside the transaction, right after the discount pass and before payment creation:

```ruby
        @allocations.each { |row| apply_discounts_for(row) }
        @allocations.each { |row| check_outstanding_after_discounts!(row) }
```

- [ ] **Step 4: Run the failing tests again**

Run: `bundle exec rspec spec/services/payments/allocate_payment_spec.rb`
Expected: all examples PASS — both the new `item_discounts` context and the pre-existing ones.

---

### Task 3: PaymentsController — forward `item_discounts` from params

**Files:**
- Modify: `app/controllers/web/customers/payments_controller.rb`

- [ ] **Step 1: Update `parsed_allocations`**

In `app/controllers/web/customers/payments_controller.rb`, replace the body of `parsed_allocations` so each allocation row carries `item_discounts` when present:

```ruby
      def parsed_allocations
        rows = params[:allocations]
        return [] if rows.blank?

        rows.to_unsafe_h.values.filter_map do |row|
          next if row[:include] != "1"
          next if row[:amount].blank? || row[:amount].to_f <= 0

          discounts_hash =
            if row[:discounts].respond_to?(:to_unsafe_h)
              row[:discounts].to_unsafe_h
            else
              row[:discounts] || {}
            end

          {
            order_id: row[:order_id],
            amount: row[:amount].to_f,
            payment_method: row[:payment_method],
            item_discounts: discounts_hash.transform_values { |v| v.to_f }
          }
        end
      end
```

The form sends discounts as `allocations[<idx>][discounts][<order_item_id>] = "<percent>"`. The hash arrives as `ActionController::Parameters` when nested under permitted params; `to_unsafe_h` flattens it. Service tolerates an empty hash (no-op).

- [ ] **Step 2: Quick sanity run**

Run: `bundle exec rspec spec/requests/web/customers/payments_spec.rb`
Expected: existing examples PASS (the new request-level coverage lands in Task 6).

---

### Task 4: View — replace orders table with cards layout

**Files:**
- Modify: `app/views/web/customers/payments/new.html.haml`

- [ ] **Step 1: Rewrite the orders block**

In `app/views/web/customers/payments/new.html.haml`, replace the `-# Orders table card` block (lines 61-111) with a card-per-order grid. Leave the header, errors block, empty state, summary card, and footer (lines 1-59 and 113-129) unchanged. Insert the following in place of the orders table card:

```haml
      -# Orders cards
      .space-y-3.mb-4
        - @pending_orders.each_with_index do |order, idx|
          - paid_so_far = order.payment_allocations.sum(:amount)
          - pending = order.outstanding_balance
          - locked = order.payment_allocations.exists?
          - paper = order.paper_number.presence
          - order_title = paper ? "Orden ##{order.id}/#{paper}" : "Orden ##{order.id}"
          .bg-white.border.border-slate-200.rounded-xl.p-4{ data: { "payment-allocation-target": "row", "pending": pending, "order-id": order.id, "locked": locked.to_s } }
            = hidden_field_tag "allocations[#{idx}][order_id]", order.id
            .flex.items-center.gap-3
              = check_box_tag "allocations[#{idx}][include]", "1", false,
                  class: "w-4 h-4 rounded border-slate-300",
                  data: { "role": "include-checkbox", action: "change->payment-allocation#toggleRow" }
              .flex-1.flex.flex-wrap.items-center.gap-x-4.gap-y-1.text-sm
                %span.font-semibold.text-slate-900= order_title
                %span.text-slate-500= l(order.sale_date || order.created_at.to_date, format: :default)
                %span.text-slate-600 Total #{currency_ar_int(order.total_amount)}
                %span.font-semibold.text-amber-600 Pendiente #{currency_ar_int(pending)}
                - if locked
                  %span.text-xs.px-2.py-0.5.rounded.bg-slate-100.text-slate-600 descuentos congelados
              %button.text-xs.text-slate-500.underline.decoration-dotted{ type: "button", data: { action: "click->payment-allocation#toggleProducts" } }
                = "#{order.order_items.size} #{'producto'.pluralize(order.order_items.size)} ▸"

            .mt-3.pt-3.border-t.border-dashed.border-slate-200.hidden{ data: { "role": "products-block" } }
              %table.w-full.text-xs
                %thead
                  %tr.text-slate-500
                    %th.text-left.py-1.font-medium.uppercase.tracking-wider Producto
                    %th.text-center.py-1.font-medium.uppercase.tracking-wider Cant.
                    %th.text-center.py-1.font-medium.uppercase.tracking-wider Desc.
                    %th.text-right.py-1.font-medium.uppercase.tracking-wider Subtotal
                %tbody
                  - order.order_items.each do |item|
                    - locked_pct = item.discount_percent.to_i
                    %tr.border-t.border-slate-100
                      %td.py-1.5= item.product&.name
                      %td.py-1.5.text-center= item.quantity
                      %td.py-1.5.text-center
                        - if locked
                          %span.text-slate-500= "#{locked_pct}% (fijado)"
                        - else
                          = select_tag "allocations[#{idx}][discounts][#{item.id}]",
                              options_for_select([["0%","0"],["5%","5"],["10%","10"],["15%","15"],["20%","20"]], locked_pct.to_s),
                              disabled: true,
                              class: "border border-slate-300 rounded px-2 py-0.5 text-xs disabled:bg-slate-50 disabled:text-slate-400",
                              data: { "role": "discount-select", "item-id": item.id, "unit-price": (item.unit_price || 0).to_f, "quantity": item.quantity, action: "change->payment-allocation#discountChanged" }
                      %td.py-1.5.text-right{ data: { "role": "subtotal-cell" } }= currency_ar_int((item.unit_price || 0) * item.quantity * (1 - locked_pct / 100.0))

              .flex.items-center.justify-between.mt-3.pt-2.text-xs
                %div{ data: { "role": "discount-summary" }, class: ("hidden" unless locked && order.discount_amount.to_f > 0) }
                  Total con descuento:
                  %span.line-through.text-slate-400{ data: { "role": "summary-original" } }= currency_ar_int(order.original_total_amount)
                  %span.mx-1 →
                  %span.font-semibold.text-slate-900{ data: { "role": "summary-new" } }= currency_ar_int(order.total_amount)
                .flex.items-center.gap-2
                  %label.text-slate-500 Cobrar
                  = number_field_tag "allocations[#{idx}][amount]", nil,
                      step: "0.01", min: "0",
                      disabled: true,
                      class: "w-32 px-2 py-1 text-right text-sm font-semibold border border-slate-300 rounded disabled:bg-slate-50 disabled:text-slate-400",
                      data: { "role": "amount-input", action: "input->payment-allocation#recalc" }
                  = select_tag "allocations[#{idx}][payment_method]",
                      options_for_select(payment_method_options, "cash"),
                      disabled: true,
                      class: "px-2 py-1 text-sm border border-slate-300 rounded disabled:bg-slate-50 disabled:text-slate-400",
                      data: { "role": "method-select" }

        %p.text-xs.text-slate-400.italic.mt-3
          Tildá una orden para incluirla en el cobro. Los descuentos se aplican una sola vez por orden y quedan fijos al primer cobro.
```

The card is the same DOM element previously used as the table row (still tagged `payment-allocation-target="row"` so the existing Stimulus targets keep working). The hidden `products-block` is the expandable section; Stimulus toggles its `hidden` class.

- [ ] **Step 2: Smoke the page locally**

If you have the dev server running, visit `/web/customers/<id>/payments/new` for a customer with credit and at least one pending credit order and verify the page renders without errors. If no dev server is available, run:

Run: `bundle exec rspec spec/requests/web/customers/payments_spec.rb -e "GET" 2>/dev/null || bundle exec rails routes -c Web::Customers::Payments`
Expected: no view-rendering exceptions. (The existing request spec covers `POST`; rendering errors would surface on `POST` retries via `render :new`.)

---

### Task 5: Stimulus controller — discount recalc and lock state

**Files:**
- Modify: `app/javascript/controllers/payment_allocation_controller.js`

- [ ] **Step 1: Replace the controller body**

Open `app/javascript/controllers/payment_allocation_controller.js` and replace its full contents with:

```javascript
import { Controller } from "@hotwired/stimulus"

// Manages the multi-order payment form with per-product discounts.
// - Each card represents one credit order.
// - Ticking a card enables inputs, prefills amount with the (possibly recalculated) pending, and expands the products block.
// - Discount selects only run when the order is unlocked (no prior allocations).
// - Locked cards render selects as read-only "(fijado)" labels in the HAML; this controller skips them.
export default class extends Controller {
  static targets = ["row", "totalCharging", "remainingBalance", "selectedCount", "submitButton"]
  static values = { totalDebt: Number }

  connect() {
    this.updateSummary()
  }

  toggleRow(event) {
    const row = event.target.closest("[data-payment-allocation-target='row']")
    this.enableRow(row, event.target.checked)
    this.updateSummary()
  }

  toggleProducts(event) {
    const row = event.target.closest("[data-payment-allocation-target='row']")
    const block = row.querySelector("[data-role='products-block']")
    block.classList.toggle("hidden")
    event.target.textContent = event.target.textContent.includes("▸")
      ? event.target.textContent.replace("▸", "▾")
      : event.target.textContent.replace("▾", "▸")
  }

  discountChanged(event) {
    const row = event.target.closest("[data-payment-allocation-target='row']")
    this.recomputeCard(row)
    this.updateSummary()
  }

  recalc() {
    this.updateSummary()
  }

  enableRow(row, enabled) {
    const amountInput = row.querySelector("[data-role='amount-input']")
    const methodSelect = row.querySelector("[data-role='method-select']")
    const productsBlock = row.querySelector("[data-role='products-block']")
    const locked = row.dataset.locked === "true"

    if (enabled) {
      amountInput.disabled = false
      methodSelect.disabled = false
      productsBlock.classList.remove("hidden")
      if (!locked) {
        row.querySelectorAll("[data-role='discount-select']").forEach(sel => { sel.disabled = false })
      }
      this.recomputeCard(row)
    } else {
      amountInput.disabled = true
      methodSelect.disabled = true
      amountInput.value = ""
      productsBlock.classList.add("hidden")
      row.querySelectorAll("[data-role='discount-select']").forEach(sel => { sel.disabled = true })
    }
  }

  recomputeCard(row) {
    const locked = row.dataset.locked === "true"
    let original = 0
    let newTotal = 0

    row.querySelectorAll("tbody tr").forEach(tr => {
      const sel = tr.querySelector("[data-role='discount-select']")
      const subtotalCell = tr.querySelector("[data-role='subtotal-cell']")
      let unit, qty, pct
      if (sel) {
        unit = parseFloat(sel.dataset.unitPrice) || 0
        qty = parseFloat(sel.dataset.quantity) || 0
        pct = parseFloat(sel.value) || 0
      } else {
        // Locked rows render the percentage as plain text; pull values from cells.
        const tds = tr.querySelectorAll("td")
        unit = 0  // unknown from DOM; locked totals are server-rendered and not recomputed.
        qty = 0
        pct = 0
      }
      const lineNew = unit * qty * (1 - pct / 100)
      const lineOriginal = unit * qty
      original += lineOriginal
      newTotal += lineNew
      if (sel && subtotalCell) {
        subtotalCell.textContent = this.formatMoney(lineNew)
      }
    })

    const summary = row.querySelector("[data-role='discount-summary']")
    if (summary && !locked) {
      if (original > 0 && Math.abs(original - newTotal) > 0.001) {
        summary.classList.remove("hidden")
        summary.querySelector("[data-role='summary-original']").textContent = this.formatMoney(original)
        summary.querySelector("[data-role='summary-new']").textContent = this.formatMoney(newTotal)
      } else {
        summary.classList.add("hidden")
      }
    }

    // Refresh pending (= newTotal − already paid).
    if (!locked) {
      const paid = parseFloat(row.dataset.pending) // server-side pending = total − paid_so_far; locked=false means paid_so_far=0
      // For unlocked orders paid_so_far is always 0, so newTotal == new pending.
      row.dataset.pending = newTotal.toFixed(2)
      const amountInput = row.querySelector("[data-role='amount-input']")
      const checkbox = row.querySelector("[data-role='include-checkbox']")
      if (checkbox.checked) {
        amountInput.value = newTotal.toFixed(2)
      }
    }
  }

  updateSummary() {
    let charging = 0
    let selected = 0

    this.rowTargets.forEach(row => {
      const checkbox = row.querySelector("[data-role='include-checkbox']")
      const amountInput = row.querySelector("[data-role='amount-input']")
      if (checkbox.checked && amountInput.value) {
        const v = parseFloat(amountInput.value) || 0
        charging += v
        if (v > 0) selected += 1
      }
    })

    const remaining = this.totalDebtValue - charging

    this.totalChargingTarget.textContent = this.formatMoney(charging)
    this.remainingBalanceTarget.textContent = this.formatMoney(remaining)
    this.selectedCountTarget.textContent = selected

    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.disabled = selected === 0
    }
  }

  formatMoney(value) {
    return "$" + Math.round(value).toLocaleString("es-AR")
  }
}
```

- [ ] **Step 2: Smoke locally**

Open the cobro screen in the browser for a customer with: (a) one unlocked credit order with multiple items, (b) one locked credit order (already partially paid). Verify:

- Ticking (a) expands the products block, enables the selects, and prefills the `Cobrar` field with the order total.
- Changing a discount on (a) recalculates the subtotal cell, the "Total con descuento" summary, and the `Cobrar` field.
- Ticking (b) expands the products block in read-only mode (selects stay disabled, "fijado" label shown), and prefills `Cobrar` with the locked pending balance.
- The top summary card (Cobrando ahora / Saldo restante) reflects the post-discount totals.

If no dev server is available, skip this and rely on Task 6's request spec.

---

### Task 6: Request spec — integration coverage

**Files:**
- Modify: `spec/requests/web/customers/payments_spec.rb`

- [ ] **Step 1: Add the failing request spec**

Append to `spec/requests/web/customers/payments_spec.rb`, inside `RSpec.describe "Web::Customers::Payments", type: :request`:

```ruby
  describe "POST with item_discounts (feat_09)" do
    let!(:stock_location_alt) { StockLocation.first || create(:stock_location) }
    let(:credit_customer) { create(:customer, :with_credit) }
    let(:product_a) do
      p = create(:product, current_stock: 0, price_unit: 100)
      create(:stock_movement, product: p, stock_location: stock_location_alt, quantity: 50, movement_type: "purchase")
      p.recalculate_current_stock!
      p
    end
    let(:credit_order) do
      Sales::CreateOrder.call(
        customer: credit_customer,
        items: [
          { product_id: product_a.id, quantity: 2, unit_price: 100 },
          { product_id: product_a.id, quantity: 1, unit_price: 100 }
        ],
        order_type: "credit"
      ).record
    end
    let(:vendedor) { create(:user, role: "vendedor") }
    before { sign_in vendedor }

    it "applies the discounts, persists the cobro, and updates customer balance" do
      items = credit_order.order_items.order(:id).to_a

      post web_customer_payments_path(credit_customer), params: {
        payment_date: Date.today.iso8601,
        allocations: {
          "0" => {
            order_id: credit_order.id.to_s,
            include: "1",
            amount: "280",
            payment_method: "cash",
            discounts: { items.first.id.to_s => "10", items.last.id.to_s => "20" }
          }
        }
      }

      expect(response).to redirect_to(web_customer_path(credit_customer))

      credit_order.reload
      expect(credit_order.original_total_amount.to_f).to eq(300.0)
      expect(credit_order.total_amount.to_f).to eq(260.0)
      expect(credit_order.payment_allocations.sum(:amount).to_f).to eq(280.0)
      credit_customer.reload
      expect(credit_customer.current_balance.to_f).to eq(260.0 - 280.0)
    end
  end
```

Note: this test posts an `amount` of 280 against a recalculated total of 260, which violates the outstanding-balance check. Use `amount: "260"` instead and adjust the expectation:

Replace the `amount: "280"` line above with `amount: "260"` and the corresponding assertions with:

```ruby
      expect(credit_order.payment_allocations.sum(:amount).to_f).to eq(260.0)
      credit_customer.reload
      expect(credit_customer.current_balance.to_f).to eq(0.0)
```

- [ ] **Step 2: Run the spec**

Run: `bundle exec rspec spec/requests/web/customers/payments_spec.rb`
Expected: all examples PASS, including the new `feat_09` context.

- [ ] **Step 3: Full sweep**

Run: `bundle exec rspec`
Expected: full suite green.

Run: `bundle exec rubocop`
Expected: 0 offenses (auto-fix with `bundle exec rubocop -a` if needed).

---

### Task 7: WORKING_CONTEXT update and commit message

**Files:**
- Modify: `WORKING_CONTEXT.md`

- [ ] **Step 1: Document the new behavior**

Find the section in `WORKING_CONTEXT.md` where feat_08 documented `order_items.discount_percent` and `orders.original_total_amount`. Append a brief feat_09 note. Concretely, add (or replace the existing sentence describing the credit-side block):

> `order_items.discount_percent` is now editable for both immediate and credit orders, capped at 0-20%. Immediate orders set the percent at order creation (capped at 10). Credit orders set per-item percent at the first `Payments::AllocatePayment` call; once any `PaymentAllocation` exists for the order, its discounts are frozen.

If the section does not exist, create it under an existing "Orders" or "Payments" heading. Keep the note short — one paragraph.

- [ ] **Step 2: Deliver the commit message to the user**

Do not run `git add` or `git commit`. Hand the following message to the user verbatim:

```
feat(feat_09): per-product discount on credit sales at payment time

Credit orders can now receive per-item discounts (0-20%) at the moment of
the first PaymentAllocation. Once any allocation lands on an order, its
discounts freeze. Payments::AllocatePayment accepts an optional
item_discounts hash per allocation, validates the cap, persists the
per-item percent, and recalculates order.total_amount post-discount.
The cobro screen renders one card per pending order with a per-product
discount select that expands on tick; locked orders show their fixed
percentages read-only.

Immediate sales (feat_08) are unchanged.
```

---

## Self-Review

**Spec coverage:**
- Rule "per-product discount cap 20%" → Task 1 + Task 2 validation step.
- Rule "locked once first allocation lands" → Task 2 second example (`ignores item_discounts when locked`).
- Rule "total_amount recalculated post-discount; original_total_amount preserved" → Task 2 first example.
- Service `Payments::AllocatePayment` extension → Task 2.
- Controller `parsed_allocations` extension → Task 3.
- UI: cards, header `#id/#paper`, expand-on-tick, locked badge, Cobrar = post-discount, per-product select 0/5/10/15/20 → Task 4.
- Stimulus: `discountChanged`, recalc summary, locked state → Task 5.
- Request-level integration → Task 6.
- WORKING_CONTEXT update → Task 7.
- Inmediate cap 10% preserved → Task 1, the immediate branch of `discount_within_order_type_cap` stays.

**Placeholder scan:** No "TBD", "TODO", or "handle edge cases" entries. Every code step shows full code.

**Type consistency:**
- `item_discounts` is consistently a `Hash<order_item_id (Integer/String), percent (Numeric/String)>` across service, controller, and request spec.
- View uses `allocations[#{idx}][discounts][item.id]` → controller maps `discounts` → `item_discounts` for the service.
- `data: { "role": "discount-select" }` referenced in Task 4 (HAML) and Task 5 (Stimulus).
- `data-locked` attribute set in Task 4, read in Task 5.

No gaps detected.
