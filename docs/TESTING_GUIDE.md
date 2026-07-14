# TESTING_GUIDE.md

Reference for the testing doctrine defined in `AGENTS.md` → "Testing Rules". This file holds the money-flow catalog and worked examples. The rules (**A** wire-format, **B** hostile input, **C** authorization matrix) and the decision tree live in `AGENTS.md`; this is consultation material.

## Running the suite

- `bundle exec rspec` — default net. Fast, **no browser**; system specs excluded. Coverage reported, not enforced.
- `FULL=1 bundle exec rspec` — adds system specs (Cuprite / headless Chrome) **and** enforces the SimpleCov floor.

## What counts as a "money flow"

A flow that creates, persists, or computes amounts, discounts, balances, or prices. Two kinds, tested differently.

### Write-money (amount params come in → require a Rule B hostile-input case)

- `Sales::CreateOrder` — per-item `unit_price` + write-back to `product.price_unit`
- `Payments::AllocatePayment` — per-order amounts + `item_discounts`
- `Payments::CollectSaleNote` — 0/5/10 cash-only discount, multi-tender
- `Payments::CollectOnAccount` — `amount_to_settle`, discount, lowers `total_amount`
- `Invoices::CreateSimpleInvoice` / `MarkAsPaid` / `ProcessPayment` — amounts + `AppliedCredit`
- Credit notes CRUD — `amount`, `exchange_rate`

### Read-money (no input to attack, but calculation correctness is critical → unit/request with seeded data)

- `Customer#current_balance` / `Order#outstanding_balance` — balance formulas
- `Order#discount_amount` / `Order#rounding_amount` — the discount and the rounding remainder are **separate** lines; deriving the discount from `total_amount` mixes them (historical bug — see `WORKING_CONTEXT.md`)

### Cross-language (the rule exists twice → requires a Rule A system spec)

- **`Payments::CashRounding`** (`app/services/payments/cash_rounding.rb`) — `round_to_nearest_hundred`: nearest multiple of 100, remainder of exactly 50 rounds **DOWN** (`BigDecimal`, `:half_down`).

  **The same rule is re-implemented in JavaScript** in `app/javascript/helpers/cash_rounding.js` (`roundToNearestHundred`), which is imported by **four** Stimulus controllers: `sale_note_payment_controller`, `payment_allocation_controller`, `on_account_payment_controller`, `order_form_controller`. The JS prefills/mirrors the amount the operator sees; the Ruby decides what is actually persisted.

  Two independent implementations of one rounding rule, and **nothing proves they agree**. A half-up JS vs half-down Ruby divergence at exactly `x.50` shows the operator one number and banks another — invisible to every unit spec, because each side passes its own. This is the textbook **Rule A** case: a system spec must drive the real form and assert the **persisted** value.

### Dormant / reserved (not a money flow — do not add specs speculatively)

- `Inventory::AdjustStock` — quantity, not money; stock has its own critical rule (see `CLAUDE.md`). **Currently not reachable from the UI**: `Web::Products::StockMovementsController` and its `new` view exist, but **no view links to them**, and `Sales::CancelOrder#reverse_stock_movements` is **commented out** ("until we have a updated stock"). Live callers today are `Purchasing::*` (no web UI) and `Inventory::SyncFromCsv` (rake-only). Treat as **reserved for the upcoming stock feature** — it is wired but dormant, not dead.
- `Inventory::MarkDelivered` — delivery state, not money.

> This catalog is derived from WORKING_CONTEXT's active-services list — verify each entry against code when it changes. The Builder adds a new entry here whenever a feature introduces a new money flow (see `AGENTS.md` → "Testing Rules" → Responsibilities). It is a helper for completeness, not the gate that decides a test layer — the decision tree does that.

---

## Worked example — Rule B: hostile input on a money flow

The backend must not trust the client to send a clean number. Ruby's `.to_f` does not validate, it guesses — and guesses wrong with the app's own AR format:

```ruby
"1.500.000,50".to_f   # => 1.5      (stops at the first dot)
"abc".to_f            # => 0.0      (no error)
"1500.50".to_f        # => 1500.5   (fine — until a normalizer touches it)
```

A request spec for any write-money flow POSTs hostile values **directly, bypassing the Stimulus normalization**, and asserts the backend rejects or normalizes them — never silently accepts a wrong number:

```ruby
RSpec.describe "POST /web/orders", type: :request do
  before { sign_in create(:user, role: "vendedor") }

  # Each value must be rejected — never silently coerced into a wrong number.
  hostile = {
    "AR-thousands"  => "1.500.000,50",
    "clean-decimal" => "1500.50",
    "non-numeric"   => "abc",
    "negative"      => "-500",
    "blank"         => ""
  }

  hostile.each do |label, value|
    it "does not persist a wrong unit_price for #{label}" do
      post web_orders_path, params: order_params_with_price(value)

      # Either rejected outright, or stored as the exact intended amount —
      # never a silently mangled one.
      expect(Order.last&.order_items&.first&.unit_price).not_to eq(1.5)
      expect(Order.last&.order_items&.first&.unit_price).not_to eq(150_050.0)
    end
  end
end
```

**`"1500.50"` is the case authors skip** because it "looks valid". It is the one that catches a normalizer doing `gsub(".", "")` unconditionally to strip AR thousands separators: that turns `"1500.50"` into `"150050"` → `150050.0`, a **100× overcharge** that no other hostile value exposes.

A system spec is the wrong place for Rule B: Stimulus would sanitize the value, so the backend's defense would never run.

---

## Worked example — Rule A: wire-format contract

Rule B proves the backend survives a *hostile* payload. Rule A proves the backend agrees with the payload **the real form actually sends** — which is a different question, and the one no other layer asks.

The seam: `sale_note_payment_controller` computes the cash to collect in JS and shows it to the operator; `Payments::CollectSaleNote` recomputes it in Ruby and persists it. Both round via their own copy of the nearest-hundred rule. A request spec cannot catch a divergence here, because the author writes the payload by hand — encoding the very assumption under test.

So: drive the **real form** in a **real browser**, and assert the **persisted** value.

```ruby
RSpec.describe "Cobro de nota — wire format", type: :system do
  let(:caja)  { create(:user, role: "caja") }
  let(:order) { create(:order, :immediate, total_amount: 710_775, original_total_amount: 710_775) }

  before { login_as(caja, scope: :user) }

  it "persists the same rounded cash the operator saw" do
    visit new_web_sale_note_payment_path(order)
    select "10", from: "discount_percent"
    select "Efectivo", from: "payment_method"
    click_button "Registrar cobro"

    # 710_775 * 0.90 = 639_697.5 → nearest hundred (half_down) = 639_700.
    # Asserting the PERSISTED value, not the rendered text: the screen can be
    # right while the DB is wrong. That gap is the whole point of Rule A.
    expect(order.reload.total_amount).to eq(639_700)
  end
end
```

Assert on the **database**, not on rendered text. Rendered text is produced by the same JS whose correctness is in question — asserting on it would let the two implementations agree with each other while both disagree with the backend.

Rule A specs run only under `FULL=1`.

---

## Worked example — Rule C: authorization matrix

A policy unit spec proves the *policy* is right. It does **not** prove the controller *calls* it — a missing `authorize` fails **open**, and the action just runs. Only a request spec catches that.

Drive it from a table, so adding a role or a route forces the matrix to be updated rather than silently under-tested:

```ruby
RSpec.describe "Authorization matrix", type: :request do
  # role => expected HTTP outcome. :ok = allowed, :redirect = bounced by Pundit.
  {
    "vendedor" => :redirect,
    "caja"     => :ok,
    "admin"    => :ok
  }.each do |role, outcome|
    it "#{role} → #{outcome} on the sale-note collect form" do
      sign_in create(:user, role: role)
      get new_web_sale_note_payment_path(create(:order, :immediate))

      outcome == :ok ? expect(response).to(have_http_status(:ok))
                     : expect(response).to(redirect_to(root_path))
    end
  end
end
```
