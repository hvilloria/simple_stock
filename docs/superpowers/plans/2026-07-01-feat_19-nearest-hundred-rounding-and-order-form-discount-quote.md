# feat_19 — Nearest-100 rounding + order-form cash-discount quote — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Change discounted-cash rounding from *ceil-to-100* to *nearest-100 (ties round down)* everywhere, add a JS-only cash-discount quote to the new-order form, and make the order-detail "Redondeo" line sign-aware.

**Architecture:** One shared Ruby helper (`Payments::CashRounding`) already centralizes the backend rule; its callers (`CollectSaleNote`, `CollectOnAccount`, `PaymentsOnAccount::PaymentsController`) get updated. The JS rule, today duplicated inline in 4 controllers, gets extracted into one importmap-pinned helper (`app/javascript/helpers/cash_rounding.js`). The order-form quote is display-only Stimulus state — no new form fields, backend untouched.

**Tech Stack:** Rails 7.2, HAML, TailwindCSS, Stimulus (importmap, no bundler), RSpec, BigDecimal.

## Global Constraints

- **Commits — language English only**, format `type(feat_19): title` + blank line + body. Scope is **`feat_19`**, constant across every commit on this branch. No `Co-Authored-By` / "Generated with Claude" / any Anthropic mention.
- **Never run `git commit` unless the user explicitly asks in that message.** Every "commit" step below means: stage the files and hand the user the message text; do **not** invoke `git commit` yourself.
- **One logical change per commit.** This plan maps to exactly 3 commits (A, B, C — noted per task group).
- UI copy / locales / enums stay **Spanish**; code comments and this doc are **English** (already the repo convention).
- Frontend follows `docs/UI_DESIGN_SPEC.md`: slate base, no new accent colors.
- Stock rule is irrelevant here (no stock touched) but do not violate it incidentally.

---

## File Structure

- `app/services/payments/cash_rounding.rb` — **modify**: rename/redefine to `round_to_nearest_hundred`.
- `spec/services/payments/cash_rounding_spec.rb` — **modify**: new boundary table.
- `app/services/payments/collect_sale_note.rb` — **modify**: call site + comments (numbers unchanged).
- `app/services/payments/collect_on_account.rb` — **modify**: call site + comments.
- `spec/services/payments/collect_on_account_spec.rb` — **modify**: one case's numbers change.
- `app/controllers/web/payments_on_account/payments_controller.rb` — **modify**: inline ceil → nearest.
- `app/javascript/helpers/cash_rounding.js` — **create**: `roundToNearestHundred`.
- `config/importmap.rb` — **modify**: pin the new helpers dir.
- `app/javascript/controllers/sale_note_payment_controller.js` — **modify**: use helper.
- `app/javascript/controllers/on_account_payment_controller.js` — **modify**: use helper.
- `app/javascript/controllers/payment_allocation_controller.js` — **modify**: use helper.
- `app/javascript/controllers/order_form_controller.js` — **modify**: discount-quote state + helper.
- `app/views/web/orders/new.html.haml` — **modify**: discount-quote UI in the summary panel.
- `app/views/web/orders/show.html.haml` — **modify**: sign-aware Redondeo line (2 spots).
- `spec/models/order_spec.rb` — **modify**: add negative-rounding example.

---

## Task 0: Create the feature branch

- [ ] **Step 1: Create and switch to the branch** (currently on `main`)

Run:
```bash
git checkout -b feat_19-nearest-hundred-rounding
```
Expected: `Switched to a new branch 'feat_19-nearest-hundred-rounding'`

---

## COMMIT A — `feat(feat_19): round discounted cash to nearest hundred`
_Tasks 1–3. Stage + hand over the message at the end of Task 3._

### Task 1: Redefine `Payments::CashRounding` to nearest-100 (half-down)

**Files:**
- Modify: `app/services/payments/cash_rounding.rb`
- Test: `spec/services/payments/cash_rounding_spec.rb`

**Interfaces:**
- Produces: `Payments::CashRounding.round_to_nearest_hundred(amount) -> Integer`. Rounds to the nearest multiple of 100; a remainder of exactly 50 rounds **down**. Replaces the old `round_up_to_hundred`.

- [ ] **Step 1: Rewrite the spec** — replace the entire body of `spec/services/payments/cash_rounding_spec.rb` with:

```ruby
require "rails_helper"

RSpec.describe Payments::CashRounding do
  describe ".round_to_nearest_hundred" do
    {
      639_697.5 => 639_700,  # remainder 97,5 → up
      22_050    => 22_000,   # remainder 50 (tie) → down
      22_051    => 22_100,   # remainder 51 → up
      50        => 0,        # tie → down
      51        => 100,      # → up
      150       => 100,      # remainder 50 (tie) → down
      151       => 200,      # → up
      900       => 900,      # exact multiple
      1_000     => 1_000,    # exact multiple
      0         => 0
    }.each do |input, expected|
      it "rounds #{input} to nearest hundred => #{expected}" do
        expect(described_class.round_to_nearest_hundred(input)).to eq(expected)
      end
    end

    it "returns an Integer" do
      expect(described_class.round_to_nearest_hundred(450)).to be_a(Integer)
    end
  end
end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bundle exec rspec spec/services/payments/cash_rounding_spec.rb`
Expected: FAIL — `NoMethodError: undefined method 'round_to_nearest_hundred'`.

- [ ] **Step 3: Rewrite the helper** — replace the whole body of `app/services/payments/cash_rounding.rb` with:

```ruby
# frozen_string_literal: true

module Payments
  # Shared rounding rule for discounted cash collections.
  #
  # When a discount is granted AND the amount is paid in cash, the cash to
  # collect is rounded to the NEAREST multiple of 100, with a remainder of
  # exactly 50 rounding DOWN (remainder 1–50 → down, 51–99 → up). Uses
  # BigDecimal to avoid float drift. Always returns an Integer.
  #
  #   round_to_nearest_hundred(22_050)  => 22_000
  #   round_to_nearest_hundred(22_051)  => 22_100
  #   round_to_nearest_hundred(639_697.5) => 639_700
  #   round_to_nearest_hundred(900)      => 900
  module CashRounding
    module_function

    def round_to_nearest_hundred(amount)
      ((amount.to_d / 100).round(0, :half_down) * 100).to_i
    end
  end
end
```

- [ ] **Step 4: Run the spec to verify it passes**

Run: `bundle exec rspec spec/services/payments/cash_rounding_spec.rb`
Expected: PASS (11 examples).

### Task 2: Update backend callers to the new method

**Files:**
- Modify: `app/services/payments/collect_sale_note.rb:92` (+ comments at 89–92, 99–100)
- Modify: `app/services/payments/collect_on_account.rb:106` (+ comments at 111–113)
- Modify: `app/controllers/web/payments_on_account/payments_controller.rb:15-18`
- Test: `spec/services/payments/collect_on_account_spec.rb` (one case changes)

**Interfaces:**
- Consumes: `Payments::CashRounding.round_to_nearest_hundred` (Task 1).

- [ ] **Step 1: `collect_sale_note.rb`** — in `#effective_total` change the call and comment:

Replace (around line 89–93):
```ruby
    def effective_total
      @effective_total ||= begin
        raw = (@order.original_total_amount.to_d * (1 - @discount_percent.to_d / 100)).round(2)
        @discount_percent.positive? ? round_up_to_hundred(raw) : raw
      end
    end
```
with:
```ruby
    def effective_total
      @effective_total ||= begin
        raw = (@order.original_total_amount.to_d * (1 - @discount_percent.to_d / 100)).round(2)
        @discount_percent.positive? ? round_to_nearest_hundred(raw) : raw
      end
    end
```
Then in `#apply_discount!` update the comment (line ~99–100): change `cash ceil-to-hundred` to `cash nearest-hundred`.

- [ ] **Step 2: `collect_on_account.rb`** — in `#cash_to_collect` (line ~103–108) change the call:

Replace `@discount_percent.positive? ? round_up_to_hundred(raw) : raw`
with `@discount_percent.positive? ? round_to_nearest_hundred(raw) : raw`.
Update the `#apply_discount!` comment (line ~111–112): `ceil-to-hundred` → `nearest-hundred`.

- [ ] **Step 3: `payments_on_account/payments_controller.rb`** — replace lines 15–18:

```ruby
        cash_raw = amount - (amount * discount / 100).round(2)
        # Discounted cash collections round UP to the next hundred (must match
        # Payments::CollectOnAccount#cash_to_collect so validation passes).
        cash     = discount.positive? ? (cash_raw / 100.0).ceil * 100 : cash_raw
```
with:
```ruby
        cash_raw = amount - (amount * discount / 100).round(2)
        # Discounted cash collections round to the NEAREST hundred (must match
        # Payments::CollectOnAccount#cash_to_collect so validation passes).
        cash     = discount.positive? ? ::Payments::CashRounding.round_to_nearest_hundred(cash_raw) : cash_raw
```

- [ ] **Step 4: Fix the one changed `collect_on_account_spec.rb` case** — the non-multiple partial (250.001 × 0,90 = 225.000,9 → **nearest = 225.000**, not 225.100). Replace that example (around lines 63–74):

```ruby
    # cash_raw NOT a multiple: 250.001 × 0,90 = 225.000,9 → nearest-100 = 225.000.
    it "rounds a non-multiple partial cash to the nearest hundred" do
      result = described_class.call(
        order: big_order, amount_to_settle: 250_001,
        discount_percent: 10, tenders: [ { payment_method: "cash", amount: 225_000 } ]
      )

      expect(result).to be_success
      expect(big_order.reload.total_amount).to eq(685_774)         # 710.775 − 25.001 effective discount
      expect(big_order.payment_allocations.sum(:amount)).to eq(225_000)
      expect(big_order.outstanding_balance).to eq(460_774)
    end
```

Note: the two other discount cases in this spec (639.697,5 → 639.700 and the 300.000 exact-multiple case) are **unchanged** under nearest-100 — do not touch them. `collect_sale_note_spec.rb` is unchanged (its only rounding case, 639.700, is identical under both rules).

- [ ] **Step 5: Run the affected specs**

Run: `bundle exec rspec spec/services/payments/`
Expected: PASS (all payments specs green).

- [ ] **Step 6: Run the full suite to catch any other fixture that assumed ceil**

Run: `bundle exec rspec`
Expected: PASS. If a request/system spec asserted a ceil-rounded total that now rounds down, update the expected number to the nearest-100 value (recompute as `round_to_nearest_hundred(discounted_raw)`).

### Task 3: Extract the shared JS rounding helper and swap the 3 collection controllers

**Files:**
- Create: `app/javascript/helpers/cash_rounding.js`
- Modify: `config/importmap.rb`
- Modify: `app/javascript/controllers/sale_note_payment_controller.js:88`
- Modify: `app/javascript/controllers/on_account_payment_controller.js:30`
- Modify: `app/javascript/controllers/payment_allocation_controller.js:117`

**Interfaces:**
- Produces: `roundToNearestHundred(amount) -> number` exported from `helpers/cash_rounding`. Nearest multiple of 100; exactly `.50` fractional part rounds **down** (matches backend `:half_down`).

- [ ] **Step 1: Create the helper** — `app/javascript/helpers/cash_rounding.js`:

```javascript
// Round to the nearest multiple of 100; a remainder of exactly 50 rounds DOWN
// (remainder 1–50 → down, 51–99 → up). Mirrors the backend
// Payments::CashRounding.round_to_nearest_hundred (:half_down).
export function roundToNearestHundred(amount) {
  const v = amount / 100
  const floor = Math.floor(v)
  return (v - floor > 0.5 ? floor + 1 : floor) * 100
}
```

- [ ] **Step 2: Pin the helpers dir** — in `config/importmap.rb`, add after the controllers pin line:

```ruby
pin_all_from "app/javascript/helpers", under: "helpers"
```

- [ ] **Step 3: `sale_note_payment_controller.js`** — add the import at the top (after the Stimulus import):

```javascript
import { roundToNearestHundred } from "helpers/cash_rounding"
```
Then replace line 88:
```javascript
    return discount > 0 ? Math.ceil(raw / 100) * 100 : +raw.toFixed(2)
```
with:
```javascript
    return discount > 0 ? roundToNearestHundred(raw) : +raw.toFixed(2)
```

- [ ] **Step 4: `on_account_payment_controller.js`** — add the same import at the top, then replace line 30:
```javascript
    const cash = (discount > 0 && isCash) ? Math.ceil(cashRaw / 100) * 100 : cashRaw
```
with:
```javascript
    const cash = (discount > 0 && isCash) ? roundToNearestHundred(cashRaw) : cashRaw
```

- [ ] **Step 5: `payment_allocation_controller.js`** — add the same import at the top, then replace line 117:
```javascript
    const chargeable = (isCash && hasDiscount) ? Math.ceil(newSum / 100) * 100 : newSum
```
with:
```javascript
    const chargeable = (isCash && hasDiscount) ? roundToNearestHundred(newSum) : newSum
```

- [ ] **Step 6: Manual smoke check** (no JS test harness in this repo)

Run the app (`bin/rails s`), open a caja Sale-Note collection with a 10% cash discount on a total whose discounted value ends in …50 (e.g. subtotal that yields `x.050`). Confirm the "a cobrar" amount now rounds **down** to the hundred and matches what the backend accepts (no "el total debe coincidir" error on submit).

- [ ] **Step 7: Prepare COMMIT A** — stage and hand over the message (do **not** run `git commit`):

```bash
git add app/services/payments/cash_rounding.rb spec/services/payments/cash_rounding_spec.rb \
  app/services/payments/collect_sale_note.rb app/services/payments/collect_on_account.rb \
  spec/services/payments/collect_on_account_spec.rb \
  app/controllers/web/payments_on_account/payments_controller.rb \
  app/javascript/helpers/cash_rounding.js config/importmap.rb \
  app/javascript/controllers/sale_note_payment_controller.js \
  app/javascript/controllers/on_account_payment_controller.js \
  app/javascript/controllers/payment_allocation_controller.js
```
Message to hand to the user:
```
feat(feat_19): round discounted cash to nearest hundred

Replace the ceil-to-100 rule for discounted cash collections with
round-to-nearest-100, ties rounding down (remainder 1–50 → down,
51–99 → up). CashRounding#round_up_to_hundred becomes
#round_to_nearest_hundred; CollectSaleNote, CollectOnAccount and the
payments-on-account controller call it. Extract the duplicated JS rule
into helpers/cash_rounding.js (importmap-pinned) and use it from the
sale-note, on-account and payment-allocation controllers.
```

---

## COMMIT B — `feat(feat_19): suggest cash discount on the new-order form`
_Task 4. Stage + hand over the message at the end._

### Task 4: Cash-discount quote on `web/orders/new` (display-only)

**Files:**
- Modify: `app/views/web/orders/new.html.haml` (summary panel, around lines 125–128)
- Modify: `app/javascript/controllers/order_form_controller.js`

**Interfaces:**
- Consumes: `roundToNearestHundred` from `helpers/cash_rounding` (Task 3).
- Produces: no server-facing interface. The `<select>` has **no `name`**, so it is never submitted; `Sales::CreateOrder` params are byte-for-byte unchanged.

- [ ] **Step 1: Add the quote UI** — in `app/views/web/orders/new.html.haml`, insert the following block immediately after the main-total block (after line 128, the `%p.text-4xl...{ data: { order_form_target: "total" } } $0`, still inside `.text-center.mb-6`'s sibling area — place it as a new sibling before the `.border-t.border-gray-200.py-4.space-y-3` items block at line 130):

```haml
          -# Cash-discount quote (Contado only). Salesperson suggestion — NOT
          -# submitted; caja applies the real discount at collection.
          .border-t.border-gray-200.py-4.hidden{ data: { order_form_target: "discountSection" } }
            %label.block.text-sm.font-medium.text-gray-700.mb-2{ for: "suggested_discount" } Descuento sugerido (contado)
            %select#suggested_discount{ data: { order_form_target: "discountSelect", action: "change->order-form#updateDiscountSuggestion" }, class: "w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-gray-700 focus:border-transparent transition-all" }
              %option{ value: "0" } Sin descuento
              %option{ value: "5" } 5%
              %option{ value: "10" } 10%
            .flex.justify-between.items-center.mt-3
              %span.text-sm.text-gray-600 Total con descuento
              %span.text-xl.font-bold.text-gray-900{ data: { order_form_target: "suggestedTotal" } } $0
            %p.text-xs.text-gray-500.mt-1 El descuento final lo aplica caja al cobrar.
```

Note: `%select#suggested_discount` intentionally has **no `name`** — browsers do not submit named-less controls, so the order params stay unchanged.

- [ ] **Step 2: Import the helper and register targets** — in `app/javascript/controllers/order_form_controller.js`:

Add at the top, after the Stimulus import (line 1):
```javascript
import { roundToNearestHundred } from "helpers/cash_rounding"
```
Extend the `static targets` array (line 4) to include the three new targets:
```javascript
  static targets = ["items", "total", "itemCount", "totalQuantity", "submitButton", "orderTypeInfo", "creditRadio", "immediateRadio", "onAccountRadio", "contactSection", "deliveredLabel", "discountSection", "discountSelect", "suggestedTotal"]
```

- [ ] **Step 3: Add the helper methods** — add these three methods to the controller class (e.g. just after `updateSummary`, before `updateSubmitButton`):

```javascript
  currentOrderType() {
    const checked = this.element.querySelector('input[name="order[order_type]"]:checked')
    return checked ? checked.value : "immediate"
  }

  applyDiscountSectionVisibility(orderType) {
    if (!this.hasDiscountSectionTarget) return
    const isImmediate = orderType === "immediate"
    this.discountSectionTarget.classList.toggle("hidden", !isImmediate)
    if (!isImmediate && this.hasDiscountSelectTarget) {
      this.discountSelectTarget.value = "0"
    }
    this.updateSuggestedTotal()
  }

  updateDiscountSuggestion() {
    this.updateSuggestedTotal()
  }

  updateSuggestedTotal() {
    if (!this.hasSuggestedTotalTarget) return
    const total = this.calculateTotal()
    const discount = this.hasDiscountSelectTarget ? parseInt(this.discountSelectTarget.value) || 0 : 0
    const suggested = discount > 0 ? roundToNearestHundred(total * (1 - discount / 100)) : total
    this.suggestedTotalTarget.textContent = `$${this.formatAmount(suggested)}`
  }
```

- [ ] **Step 4: Wire it into connect / updateSummary / updateOrderType**

In `connect()` (ends at line 12), add as the last line:
```javascript
    this.applyDiscountSectionVisibility(this.currentOrderType())
```
In `updateSummary()`, add a call at the end of the method (after the `updateSubmitButton()` call is fine):
```javascript
    this.updateSuggestedTotal()
```
In `updateOrderType(event)`, add at the end of the method (after `this.toggleDeliveredLabels()`):
```javascript
    this.applyDiscountSectionVisibility(orderType)
```

- [ ] **Step 5: Manual verification** (JS-only UI, no request-spec change)

Run the app, open `/web/orders/new`:
1. Default type is Contado → the discount block is visible, "Total con descuento" mirrors Total at 0%.
2. Add products; select 10% → suggested total = nearest-100 of `total × 0,90` (e.g. total 24.500 → shows `$22.000`).
3. Switch to Cuenta Corriente / Pago a cuenta → block hides and select resets to 0%. Switch back to Contado → block shows again at 0%.
4. Submit the order → confirm the created order has **no discount** (caja still collects full total). Params unchanged.

- [ ] **Step 6: Prepare COMMIT B** — stage and hand over the message (do **not** run `git commit`):

```bash
git add app/views/web/orders/new.html.haml app/javascript/controllers/order_form_controller.js
```
Message to hand to the user:
```
feat(feat_19): suggest cash discount on the new-order form

Add a Contado-only discount selector (0/5/10) to the sale summary that
shows the nearest-100 discounted total, so the salesperson can quote a
cash price. Display-only: the control has no name and is not submitted;
caja still applies the real discount at collection.
```

---

## COMMIT C — `fix(feat_19): show signed rounding on order detail`
_Task 5. Stage + hand over the message at the end._

### Task 5: Sign-aware Redondeo line on `web/orders/show`

**Files:**
- Modify: `app/views/web/orders/show.html.haml:171-174` and `:305-308`
- Test: `spec/models/order_spec.rb` (add a negative-rounding example under `#rounding_amount`)

**Interfaces:**
- Consumes: `Order#rounding_amount` (already returns a signed value; no model change).

- [ ] **Step 1: Add a failing model example** — in `spec/models/order_spec.rb`, inside the `describe "#rounding_amount"` block, add this example (after the existing "+50" example around line 358):

```ruby
    it "returns a NEGATIVE surcharge when nearest-100 rounded the total down" do
      # neto nominal 24.500 − 2.450 = 22.050; nearest-100 total 22.000 => redondeo −50
      order = Order.create!(customer: customer, order_type: "immediate", source: "live", paper_number: "9011",
                            sale_date: Date.current, total_amount: 22_000, original_total_amount: 24_500,
                            status: "confirmed", user: create(:user))
      order.order_items.create!(product: product, quantity: 1, unit_price: 24_500, discount_percent: 10)
      expect(order.rounding_amount).to eq(-50)
    end
```

- [ ] **Step 2: Run it — it should already PASS** (the model math is unchanged; this locks in the negative behavior)

Run: `bundle exec rspec spec/models/order_spec.rb -e "#rounding_amount"`
Expected: PASS (including the new example). `rounding_amount = 22_000 − (24_500 − 2_450) = −50`.

- [ ] **Step 3: Fix the items-table footer** — in `app/views/web/orders/show.html.haml`, replace lines 171–174:

```haml
                - if @order.rounding_amount.positive?
                  %tr
                    %td.px-6.py-2.text-right.text-sm.text-gray-500{colspan: "5"} Redondeo
                    %td.px-6.py-2.text-right.text-sm.text-gray-500= "+#{currency_ar(@order.rounding_amount)}"
```
with:
```haml
                - unless @order.rounding_amount.zero?
                  %tr
                    %td.px-6.py-2.text-right.text-sm.text-gray-500{colspan: "5"} Redondeo
                    %td.px-6.py-2.text-right.text-sm.text-gray-500= "#{@order.rounding_amount.positive? ? '+' : '−'}#{currency_ar(@order.rounding_amount.abs)}"
```

- [ ] **Step 4: Fix the summary panel** — replace lines 305–308:

```haml
            - if @order.rounding_amount.positive?
              .flex.justify-between.text-sm
                %span.text-gray-600 Redondeo
                %span.font-medium.text-gray-900= "+#{currency_ar(@order.rounding_amount)}"
```
with:
```haml
            - unless @order.rounding_amount.zero?
              .flex.justify-between.text-sm
                %span.text-gray-600 Redondeo
                %span.font-medium.text-gray-900= "#{@order.rounding_amount.positive? ? '+' : '−'}#{currency_ar(@order.rounding_amount.abs)}"
```

Note: `currency_ar(@order.rounding_amount.abs)` uses the magnitude so the unicode "−" is applied once (matches the "−" style already used for the Descuento line); passing a raw negative would render an ASCII "-" and double the sign.

- [ ] **Step 5: Manual verification** — open the show page of an immediate order collected with a discount whose discounted total rounded **down** (created after Commit A). Confirm the Redondeo line reads `−50` (or the right sign) and that Subtotal − Descuento + Redondeo = Total visibly reconciles. Check both the items-table footer and the right-side summary.

- [ ] **Step 6: Run the full suite**

Run: `bundle exec rspec`
Expected: PASS.

- [ ] **Step 7: Prepare COMMIT C** — stage and hand over the message (do **not** run `git commit`):

```bash
git add app/views/web/orders/show.html.haml spec/models/order_spec.rb
```
Message to hand to the user:
```
fix(feat_19): show signed rounding on order detail

Nearest-100 rounding can now lower the total, so the Redondeo line on
the order detail can be negative. Render it whenever it is non-zero with
an explicit +/− sign (using the absolute value), keeping
Subtotal − Descuento + Redondeo = Total reconciled in both directions.
```

---

## Self-Review

**Spec coverage:**
- Part A rounding rule → Tasks 1 (helper), 2 (backend callers + specs), 3 (JS). ✓
- Part B order-form quote → Task 4. ✓
- Part C signed show-view rounding → Task 5. ✓
- Testing section of spec → cash_rounding_spec (Task 1), collect_on_account_spec (Task 2), full suite (Task 2/5), order_spec negative case (Task 5), manual JS checks (Tasks 3/4). ✓

**Placeholder scan:** No TBD/TODO; every code step shows the full replacement. ✓

**Type/name consistency:** `round_to_nearest_hundred` (Ruby) and `roundToNearestHundred` (JS) used consistently across Tasks 1–4. New Stimulus targets `discountSection` / `discountSelect` / `suggestedTotal` match between HAML (Task 4 Step 1) and JS (Task 4 Steps 2–4). ✓

**Commit boundaries:** 3 commits (A/B/C), each an independently testable deliverable; matches the spec's commit plan and the one-logical-change rule. ✓
