# Invoices with items + stock reactivation — Design

**Pendiente #2:** "feature -> load invoices with products in them that impact
the stock, it will change the WORKING_CONTEXT.md file .. also keep in mind that
with soft deletion prob the stock movement now needs to change."

Date: 2026-07-08 · Revised: 2026-07-09 (after review — 12 decisions locked)

## Goal

Reactivate the stock lifecycle, which today is fully built but deliberately
switched off:

1. **Invoices (purchases → stock IN).** The invoice create form gains an
   **optional** product-lines section. When lines are present, the invoice
   **increases** each product's stock and its total is **computed from the lines**;
   when absent, it behaves exactly like today's amount-only invoice. Either way the
   total flows into the existing accounts-payable ("pending to pay") flow untouched.
2. **Orders (sales → stock OUT).** Creating a sale **decreases** stock for the
   products sold. Stock decrements down to 0 and **never goes negative on
   screen**; the sale always succeeds regardless of available stock.

This is largely a **reactivation**, not new machinery. See "Current reality".

## Current reality (the plumbing already exists, switched off)

- **`Purchasing::CreatePurchase`** builds a `has_items: true` invoice with items
  and recalculates average cost; its `create_stock_movements` is **commented
  out** (`app/services/purchasing/create_purchase.rb:31`). Not wired to any web
  controller. We reuse its dormant movement logic but **do not** adopt its
  `has_items: true` model (see Decision A).
- **`Sales::CreateOrder`** validates stock only for `source: 'live'`, and the UI
  submits `from_paper`, so stock is never validated and **no sale movement is
  created** (`app/services/sales/create_order.rb:97-104`).
- **`Sales::CancelOrder#reverse_stock_movements`** is fully written but
  **commented out** (`app/services/sales/cancel_order.rb:17`); it currently
  reverses `item.quantity` — which is wrong under floor-at-zero (Decision B/C).
- **`Inventory::AdjustStock`** is complete, with an `allow_negative:` flag that
  defaults to reject-if-negative (`app/services/inventory/adjust_stock.rb:45-54`).
- **`StockMovement`** already tolerates soft-deleted products
  (`belongs_to :product, -> { with_deleted }`) and references `Order`/`Invoice`
  polymorphically.
- **`Product#recalculate_current_stock!`** = `sum(stock_movements.quantity)`.
  Stock is never written directly (critical rule).

## Decision A — One unified invoice flow; line items optional

**AP = Accounts Payable** — the existing "invoices" screens (`index`, `pending`,
`mark_as_paid`, credit notes, early-payment discounts) that track what is owed to
suppliers off a single flat `amount` field.

**Chosen model: one flow, not two.** An amount-only invoice and an itemized invoice
are the *same* concept — one is just "an invoice with no line items." So there is a
**single create form, a single controller action, and a single service** (Decision H).
The form always shows the invoice header plus an **optional** product-lines section.

**The `amount` invariant (this is the backbone of the whole feature):**

> `amount` is always the authoritative AP number — but its **source** depends on
> whether there are items.
> - **Items present → `amount = Σ(quantity × unit_cost)`, computed by the server.**
>   The client's live total is **display-only and never trusted.**
> - **No items → `amount` = the typed total, trusted as-is.**

On submit:

- The invoice is always created as `has_items: false`, `status: "pending"`, so it
  appears in the pending-to-pay list and every AP scope/screen works unchanged
  (`Invoice.simple_mode` = `has_items: false`). Mark-as-paid, early-payment discount
  and credit notes all read `amount` exactly as today.
- **When lines are present**, additionally create `invoice_items` rows (the line
  breakdown + the stock driver) and the `+qty` stock movements.

Scenario: `10 × 30 + 5 × 20 = 400` → store `amount = 400`, create items, stock the
products. Pending-to-pay reads `amount` → shows 400, unchanged.

**What counts as "an item".** A line counts iff it has a **product AND quantity > 0**.
Incomplete rows (product picked, quantity blank) count as *nothing* — they neither
flip the mode nor contribute to the total. This rule is identical in the front end
(deciding whether the amount field is computed vs. typed) and in the service
(deciding whether to create items + move stock). The server is authoritative.

**Create-only for line items.** Line items are set at creation and not edited
afterward (editing would desync the frozen `amount`). Header fields remain editable —
see Decision B.

### Why not other approaches (rejected)

- **Extend `has_items: true` full mode into AP:** the AP scopes filter
  `Invoice.simple_mode` and `total_amount` branches on `has_items?`, so making a
  full-mode invoice payable means auditing every money path. The "store total into
  `amount`, keep `has_items: false`" trick avoids all of it.
- **Two separate flows (itemized form/action/service alongside the amount-only
  ones):** rejected. It's one domain concept, so two parallel stacks would duplicate
  header/validation/error plumbing and drift over time. Unify at the domain level
  (optional line items); put the discipline into testing the one seam (amount:
  computed vs. typed).

## Decision B — Amount is frozen on edit when items exist

The amount-only edit/update path stays for header corrections, but for an invoice
that **has line items**, the total is owned by the lines and must not drift:

- On edit/update, when `invoice.invoice_items.present?`, the `amount` field is
  **read-only** — the controller strips `:amount` from the permitted params and the
  edit view renders the total as display (showing the line breakdown), not an input.
- **Every other header field stays editable**, including `exchange_rate` (the USD
  `amount` is fixed, but both `amount_ars` and the items' `subtotal_ars` use the same
  rate, so they move together and stay consistent).

This desync is a display/accounting concern, not a stock corruption — stock is driven
by movements, not by `amount`. Freezing only `amount` is the surgical fix.

## Decision C — Sales oversell policy (floor at zero, never negative)

The sale **always succeeds**, regardless of stock. Stock decrements as far as it
can and **stops at 0** — it is never shown negative. Blocking the sale is rejected
because stock is not 100% tracked/trusted.

**Mechanism — record only what actually left the shelf:**

- On each order line, `available = product.current_stock`;
  `decrement = [quantity, available].min`.
- If `decrement > 0`, create **one `StockMovement`** with `quantity: -decrement`,
  `movement_type: "sale"`, `reference: order`. If `decrement == 0`, create **no
  movement** (nothing physically moved).
- `current_stock` = sum of movement rows, so it lands at exactly 0 and never below.

Scenarios:

| In stock | Sold | Movement written | Shown stock |
|---------:|-----:|-----------------:|------------:|
| 3        | 2    | −2               | 1           |
| 3        | 5    | −3               | 0           |
| 0        | 5    | (none)           | 0           |

**Only `current_stock` (the sum) is user-visible; it is never negative.** A movement
row being `−n` is normal ledger bookkeeping, not "negative stock". **Stock accuracy
never gates a sale** — an imperfect `current_stock` can never block, corrupt, or stop
a transaction; it only affects informational displays (low-stock list, dashboard).

**Honest limitation:** oversold units (e.g. the 2 not covered in row 2) drop out of
inventory math — after the next purchase the count may read high until a manual
recount. Acceptable given stock is not fully trusted today.

## Decision D — Timing & symmetry (cancel reverses what actually moved)

- **Increment/decrement at creation** for both invoices and all order types
  (`immediate`, `credit`, `on_account`). Consistent single rule.
- **Cancel reverses the *actual recorded movements*, not the order/invoice line
  quantities.** One mental model on both sides of the ledger: *reverse what actually
  moved.*
  - **Sales cancel (`Sales::CancelOrder`):** reverse only the order's
    `movement_type: "sale"` rows. For each, write a compensating movement with
    `quantity: -sale.quantity` (a positive add-back), `movement_type: "adjustment"`,
    `reference: order`, into **that sale movement's own `stock_location`**. **No floor
    needed** — an add-back can never go negative. The distinct `"adjustment"` label
    keeps the order ledger self-describing (a later audit can still read the `"sale"`
    rows as the historical outflow, while the net returns to 0). Scenario: 0 in stock
    → sell 5 (no movement) → cancel → nothing to reverse → restore **0**, not 5.
  - **Invoice cancel (`Invoices::CancelInvoice`, new — Decision E):** reverse the
    invoice's `movement_type: "purchase"` rows, but **floored at zero**
    (`min(purchased_qty, current_stock)` per product), written as
    `movement_type: "adjustment"`. Unlike the sale add-back, this reversal is a
    *decrease* that could otherwise push stock negative (goods received then partly
    sold, then the invoice cancelled). Flooring keeps the screen non-negative and lets
    the cancel always succeed — the purchase-side mirror of Decision C.
- **`on_account` delivery stays a non-stock flag in v1.** `delivered_at` remains a
  pure fulfillment marker and does **not** move stock. Trade-off accepted: an
  `on_account` sale shows goods as gone at creation even if physically still on the
  shelf awaiting pickup. One rule everywhere beats a delivery-driven exception.

## Decision E — Invoice cancel becomes a service

Today `Web::InvoicesController#cancel` sets `status: "cancelled"` directly and moves
no stock; `InvoicePolicy#cancel?` (`admin? && pending_status?`) is already true for an
itemized invoice. Left as-is, cancelling an itemized invoice would leave its `+qty`
purchase movements → **phantom stock**.

- New **`Invoices::CancelInvoice.call(invoice:)`** returning a `Result`; the controller
  calls it instead of `update(status:)`. Policy unchanged (pending-only guard stays).
- **One service covers both invoice kinds with no branching**: an amount-only invoice
  has zero `invoice_items` and zero purchase movements → the reversal loop is empty →
  it just flips `status: "cancelled"`. An itemized invoice reverses its movements
  (floored, per Decision D). Reuse the dormant pattern in
  `Purchasing::CancelPurchase#reverse_stock_movements` (`cancel_purchase.rb:42`),
  adapted to read actual `purchase` movements and apply the floor. Wrap in a
  transaction.

## Decision F — Line data & cost

- Each invoice line captures **quantity + unit_cost**, entered in the invoice's
  currency (USD or ARS, same as today's invoices; USD requires an exchange rate).
- Lines drive **stock** (quantity) and the **payable total** (`Σ quantity ×
  unit_cost → amount`).
- **Average-cost recalculation is out of scope for v1** (resolved open question):
  `Product#recalculate_average_cost!` only aggregates `invoices.status = "confirmed"`
  items, whereas these payable invoices are `pending`. v1 leaves `cost_unit`
  untouched (smallest change); reconciling is a follow-up.

## Decision G — Zero-total invoices

Follows directly from the Decision A invariant:

- **No items (typed total) → keep `amount > 0`.** A lump "I owe $0" invoice is
  meaningless.
- **Items present → allow `amount ≥ 0`.** An all-free itemized invoice (warranty
  replacement / supplier freebie) legitimately sums to 0 and still moved stock.

**Implementation note (the `has_items` landmine):** because both kinds are
`has_items: false`, the model's existing `amount > 0 unless has_items?` guard
(`invoice.rb:29`) cannot tell them apart. The "trust total only when there are no
items" rule therefore lives where the submitted items are visible — the **service** is
its authority — and the model guard must key off **items presence**, not `has_items?`.
This resolves the "has_items:false with real invoice_items" open question: *presence
of items, not the flag, decides the total's source and the display.*

## Decision H — One service (`Invoices::CreateInvoice`)

- **`Invoices::CreateInvoice`** — rename/absorb `Invoices::CreateSimpleInvoice`; there
  is **no** separate `CreatePurchaseInvoice`. SRP is honored not by splitting simple vs.
  itemized (that would split by data shape and duplicate plumbing), but by delegating
  stock to `Inventory::AdjustStock` — the responsibility that genuinely deserves its own
  class is already extracted.
- One internal branch: `if items.present? → amount = Σ, create line items, move stock;
  else → amount = typed, no items, no stock`. The two bodies are **private methods**
  (`create_line_items`, `move_stock`), not classes. Promote to a strategy object only if
  the itemized path diverges substantially in a later version (YAGNI).
- **Fix the two landmines** while unifying: (1) wrap **all** writes (header + items +
  stock) in **one `ActiveRecord::Base.transaction`** so any failure rolls back; (2)
  return a **flat** `e.record.errors.full_messages` array — today's `CreateSimpleInvoice`
  returns `[ full_messages ]` (nested `[[...]]`), which the controller's `errors.join`
  then mangles. The flat array also fixes the existing amount-only error display.

## Changes

### Invoice / purchase side (stock IN)

1. **Service — `Invoices::CreateInvoice`** (Decision H): one transaction; header always;
   when items present, create `invoice_items` and call `Inventory::AdjustStock`
   (`movement_type: "purchase"`, `quantity: +qty`, `reference: invoice`,
   `stock_location: StockLocation.first!`); `amount` computed vs. typed per Decision A;
   flat error array.
2. **Service — `Invoices::CancelInvoice`** (Decision E): floored reversal of the
   invoice's `purchase` movements; empty loop for amount-only invoices.
3. **Controller** — `Web::InvoicesController`: `#create` and `#update` handle the optional
   items in the same actions (no new route); `#cancel` calls `Invoices::CancelInvoice`;
   `#update` strips `:amount` when `invoice_items.present?` (Decision B). Reuses
   `authorize Invoice, :create?`.
4. **Form (HAML)** — **reuse the existing invoice header wholesale** (supplier,
   invoice_number, currency, exchange_rate, **purchase_date**, due_date, notes,
   early-payment card) and add an **optional** repeatable item-lines section below, with a
   **searchable product dropdown (by OEM/sku)** + quantity + unit_cost per row. Search
   reuses the existing product search (`Product.search`, scoped `.active`). The amount
   field is editable when there are no lines and **read-only/computed** when lines are
   present. **Correct the summary copy**: the current "Modo Simple … el stock NO se
   actualiza" / "No actualiza stock / No recalcula costos" blurbs are false once lines
   exist — show accurate copy when items are present. Follow `UI_DESIGN_SPEC.md` (slate
   base; no ad-hoc colors).
5. **Show** — render the line-item breakdown when `invoice_items.present?` (do **not**
   gate on `has_items?`, which stays false here).

### Sales side (stock OUT)

6. **`Sales::CreateOrder`** — inside the existing transaction, after each `OrderItem` is
   created, apply the floor-at-zero decrement (Decision C): compute
   `[quantity, current_stock].min` and, if positive, `Inventory::AdjustStock`
   (`movement_type: "sale"`, negative quantity, `reference: order`,
   `stock_location: StockLocation.first!`). **Remove** the `source: 'live'`-only
   hard-block validation — stock is now impacted for **all** orders and the block is
   never used (sales always succeed).
7. **`Sales::CancelOrder`** — enable stock reversal per Decision D: reverse the order's
   `movement_type: "sale"` rows only, as `"adjustment"` compensating movements into each
   sale movement's own location. Keep `destroy_associated_allocations`.

### Soft-delete interaction (pendiente note)

8. `StockMovement` already reads `product` `with_deleted`, and `recalculate_current_stock!`
   sums the product's own rows, so a soft-deleted product keeps a coherent, frozen stock
   history — **no structural change needed**. The product dropdown offers active,
   non-deleted products via `Product.active` — note these are **two separate filters that
   both apply**: `Product.active` = `where(active: true)`, and `acts_as_paranoid`'s default
   scope independently excludes soft-deleted rows. History is preserved by the
   `with_deleted` **associations**, not by `Product.active`. Verify `Sales::CancelOrder`
   and the invoice services never crash on a later-soft-deleted product.

### Stock location & specs

9. **All new movements target `StockLocation.first!`** (consistent with every existing
   caller); the sale-cancel reversal uses the sale movement's own `stock_location`.
   Single-location is an **explicit v1 assumption** (no location picker). Specs that
   exercise any movement must seed a `StockLocation` (`.first!` raises otherwise).

## Separate cleanup work-item (own commit/PR — NOT bundled with this feature)

The `live` / `from_paper` distinction is now **dead**: every sale originates on paper
(`paper_number` is universal), stock impacts every order, and there is no "live-only"
mode to return to. The feature itself removes the only *behavioral* dependency (the
`source`-gated block in `CreateOrder`, item 6). The remaining scaffolding is vestigial
and should be removed **as a separate logical change**, because it includes a schema
migration whose blast radius should not ride inside the stock feature:

- Drop the `source` column and its inclusion validation; remove the `from_paper?`/`live?`
  predicates (`order.rb:71-77`) and `from_paper`/`live` scopes (`:62-63`); remove the
  hidden `source` field (`orders/new.html.haml:24`).
- Collapse the `total_amount` validation to a single `greater_than: 0` — **safe** because
  manual pricing already forces `unit_price > 0` on every item, so `total = Σ(qty×price)`
  is always `> 0` (the `>= 0` branch never permits anything today).
- Remove the dead **`max_stock`** payload (`orders/new.html.haml:22`,
  `order_form_controller.js:62`) — read nowhere, and now a footgun: reviving it to cap
  quantities would silently reintroduce oversell-blocking. **Rule: stock must never gate
  sale quantity or submission under floor-at-zero.**
- Delete the unused **`Inventory::SyncFromCsv`** service + `lib/tasks/inventory.rake`, and
  its `WORKING_CONTEXT` "Important gaps" reference.
- Before dropping the column, grep every `source` / `from_paper` / `live` reference across
  app + specs + seeds + factories and update them.

## Out of scope (explicit non-goals)

- No editing of invoice **line items** after creation (create-only; header fields stay
  editable except `amount` when items exist — Decision B).
- No stock movement on `on_account` delivery (`delivered_at` stays non-stock).
- No blocking of sales on insufficient stock (floor-at-zero only).
- No average-cost recalculation for pending payable invoices in v1.
- No **backfill** of historical stock movements (see below).
- No restore/trash UI; no changes to unrelated resources.

## Cutover & the honest stock baseline

There is **no backfill and no reset**. At activation, `current_stock` is taken **as-is**
— it is not physically verified, and in practice it tends to read **high**, because the
one systematic untracked historical flow was sales-out (historical itemized purchases had
no web UI). This is a known, accepted property of switching on a stock system over
untracked history, and — thanks to floor-at-zero (Decision C) — a wrong baseline **never
gates a sale**; it only makes low-stock/dashboard numbers approximate.

- **Correction path (already exists):** a stock adjustment per product
  (`products/:id/stock_movements` → `Inventory::AdjustStock`) resets that product's
  baseline when it is physically counted.
- **A high number is expected, not a bug** — document this so it is not triaged as one.
- **Future work:** a CSV mass stock-update (bulk recount) — explicitly deferred.

## WORKING_CONTEXT.md updates (after implementation)

- **Stock:** sales now create `sale` movements (floor-at-zero); invoices with items create
  `purchase` movements; both at creation; cancel reverses the actual movements
  (`sale` add-back; `purchase` floored).
- **Orders:** remove the "stock is not modified when selling today" statement; document the
  floor-at-zero decrement and the actual-movement reversal on cancel.
- **Invoices:** document the unified create flow (line items optional; `has_items: false`;
  `amount = Σ qty×cost` when itemized, typed when not; items drive stock; appears in
  pending-to-pay); `Invoices::CreateInvoice` / `Invoices::CancelInvoice`; `amount` frozen on
  edit when items exist.
- **Key constraints:** replace the "validate stock before selling (live only)" / "stock is
  not validated when selling" notes with the floor-at-zero behavior; add "stock never gates a
  sale". After the separate cleanup: drop the `source`/`from_paper` notes and the
  `SyncFromCsv` gap.

## Tests (`spec/`)

> All movement specs must seed a `StockLocation` (item 9).

- **Invoice create (service + request):**
  - Itemized: stores `amount = Σ qty×cost`, creates `invoice_items`, creates `+qty`
    `purchase` movements raising `current_stock`, appears in pending-to-pay; a client-supplied
    total is ignored in favor of `Σ`.
  - Amount-only (no items): unchanged behavior — typed `amount`, no items, no movements,
    appears in pending-to-pay (characterize this **before** refactoring the service).
  - Zero-total: itemized all-free invoice (`amount = 0`) is **allowed**; amount-only `0` is
    **rejected** (Decision G).
- **Invoice cancel (service):** cancelling an itemized invoice reverses its `purchase`
  movements floored at zero (received-then-partly-sold restores only what remains, never
  negative, cancel still succeeds); amount-only cancel just flips status.
- **Amount frozen on edit:** updating an itemized invoice ignores a submitted `amount`;
  other header fields still update.
- **Sales decrement (service):** 3→sell 2 = −2, stock 1; 3→sell 5 = −3, stock 0; 0→sell 5 =
  no movement, stock 0 (sale always succeeds).
- **Cancel symmetry (sales):** the three cases cancelled restore exactly what left
  (2, 3, 0) — never the ordered quantity; reversals are `"adjustment"` rows.
- **Never negative:** no scenario leaves `product.current_stock` below 0.
- **Soft-delete regression:** selling/invoicing then soft-deleting the product still renders
  history and cancels without a nil error.
- **AP unchanged:** an itemized invoice's `mark_as_paid` / early-payment discount /
  credit-note flows behave identically to a simple invoice of the same `amount`.
