# Stock reactivation, part 2: sales take stock off the shelf — Design

**Status:** design approved by the owner on 2026-09-22.
**Branch:** `feat-34_stock-reactivation` (same branch as part 1; the owner merges both as one), commit scope `feat_34`.
**Builds on:** `2026-07-09-invoice-items-stock-reactivation-design.md` (decisions C and D) and `2026-09-21-stock-reactivation-invoices-design.md` (part 1: invoices with lines add stock). This document **replaces July's decision D** and keeps decision C.

## Goal

Stock goes down when a product leaves the shelf, and comes back when a sale is undone — never below zero, and never stopping a sale. In the shop's words:

| kind of sale | when stock goes down |
|---|---|
| Venta inmediata, venta a crédito | when the note is created, every line — the customer leaves with the goods and the note; what is `pending` is the collection, not the handover |
| Pago a cuenta | line by line, when the line is marked **entregado** (or at creation, for the lines the customer takes right away) |
| Changing an undelivered line (`⇄ Cambiar`) | **nothing** — the goods never left the shelf |
| Cancelar | only what actually left comes back; an on_account with two delivered lines and three undelivered gives back the two |

## What changed since July, and why D is replaced

July's decision D chose "increment/decrement at creation for every order type, `delivered_at` stays a non-stock flag" for the sake of one rule. Two things make that wrong today:

- **`Sales::ReplaceOrderItem`** (feat_22, after the July spec) lets the vendor change product and quantity of an undelivered line. Under creation-time deduction every swap would have to move stock twice; under delivery-time deduction it moves nothing, because an undelivered line has taken nothing. The owner's rule — "se pueden cambiar siempre que no hayan sido marcados como entregados" — already exists in code and now also describes the stock.
- The owner stated the operator's model plainly: *"el stock debe descontarse únicamente con los productos que se marcan como entregados; no tiene sentido descontar stock de algo que ni siquiera fue entregado"*. For an immediate sale that same model puts the deduction at creation: *"lo que está en pending es el cobro, no la entrega del producto"*.

Decision C (floor at zero, the sale always succeeds) stands unchanged.

Everything else the July spec assumed about this side was checked against `main` today:

| Claim | Verdict | What the code shows |
|---|---|---|
| `Sales::CancelOrder#reverse_stock_movements` is written, commented out, and reverses `item.quantity` | holds — and it is the wrong reversal under the floor | `cancel_order.rb:17,45-58`. Since the cash module the same transaction also reverses cash (`Cash::ReversePayment`) and destroys the allocations; the stock reversal joins that transaction. |
| `Sales::CreateOrder` blocks a sale for stock only when `source: "live"`; the UI sends `from_paper` | holds | `create_order.rb:97-104`, `orders/new.html.haml` hidden `source`. The block goes; the column stays (cleanup work-item). |
| `Inventory::MarkDelivered` does not move stock | holds — it becomes the deduction point for on_account | `mark_delivered.rb`, `update_all`; the delivery form posts only the newly checked lines and the controller always sends `delivered: true`; `delivered: false` exists in the service only. |
| `Order has_many :stock_movements, as: :reference` | holds, but a per-line link is needed | undoing one line's delivery, or cancelling after a partial delivery, must know which movement belongs to which line. |
| `Inventory::AdjustStock` refuses a negative projected stock unless `allow_negative` | holds | the floor makes that guard unreachable for sales; reversals are positive. |
| The product page lists movements with a "Venta" badge | holds | `products/show.html.haml:145-169`; it prints "Order #N" in English for an `Order` reference. |
| `create(:product, current_stock: 50)` in specs | a trap, worse here | the floor reads the cached `current_stock`, then `recalculate_current_stock!` overwrites it with the movements' sum — a fixture with no movements ends **negative**. Every stock-asserting spec seeds stock through movements. |

## Decisions

**S1. Stock timing replaces July's D.** Immediate and credit: every line at `Sales::CreateOrder`. On_account: a line at the moment it is marked delivered — in `Sales::CreateOrder` for the lines in `delivered_product_ids`, in `Inventory::MarkDelivered` for the rest. `delivered_at` is no longer "a non-stock flag": it is the stock event for on_account lines.

**S2. Floor at zero, one definition (July's C).** A line takes `min(quantity, current_stock)`; if that is 0 it writes no movement. The sale, the delivery and the note are never refused for stock. `current_stock` is read fresh (`product.reload`) at the moment of the deduction, so two lines of the same product in one order deduct in sequence. The honest limitation stays: units the count did not know about are not deducted and read high until a recount.

**S3. Movements hang off the line.** `StockMovement` accepts `OrderItem` as a reference (its `reference_type` inclusion gains the value; no migration, the column is a string). `OrderItem has_many :stock_movements, as: :reference, dependent: :nullify`. `Order#sale_movements` reads them through the lines (`StockMovement.where(reference_type: "OrderItem", reference_id: order_items.select(:id))`). `Order has_many :stock_movements, as: :reference` stays as it is — nothing writes it any more.

**S4. Two inventory services own the shelf, and everyone calls them.**
- `Inventory::DeductLineStock.call(order_item:, note:)` — S2's deduction as one `sale` movement referencing the line, or a successful no-op.
- `Inventory::RestoreLineStock.call(order_item:, note:)` — puts back **whatever the line's own movements say is out** (`-order_item.stock_movements.sum(:quantity)` when positive) as one `adjustment` movement referencing the line, or a successful no-op. A line delivered, undone and delivered again nets out correctly; an undelivered line gives nothing back; a restore never needs a floor.
Both return `Result` and write only through `Inventory::AdjustStock` with `StockLocation.first!`.

**S5. `Sales::CreateOrder`** deducts each line it creates when `order_type` is not `on_account`, or when the line is in `delivered_product_ids`. The `source == "live"` stock block is removed — stock never gates a sale — and its "Insufficient stock" message with it. The `source` keyword and column stay untouched (cleanup work-item). A failed deduction raises into the transaction: no order, no lines, no movements.

**S6. `Inventory::MarkDelivered`** stops using `update_all`. In one transaction, per line of the order among the given ids: `delivered: true` — a line not yet delivered gets `delivered_at` and is deducted; a line already delivered is left alone (idempotent, although today's form never posts one). `delivered: false` — a delivered line is restored and its `delivered_at` cleared; an undelivered one is left alone. A failed movement rolls the whole call back. The controller and the policy (`deliver?` = vendedor or admin, on_account only) do not change.

**S7. `Sales::CancelOrder`** restores every line (S4's net) inside the existing transaction, before the cash reversal: `cancel_order → restore_stock → reverse_cash_movements → destroy_associated_allocations`. A failure anywhere leaves status, stock, cash and allocations exactly as they were. The `reason` still becomes the movement's note. The three dormant "stock movements temporarily disabled" examples are rewritten to what the floor makes true.

**S8. `Sales::ReplaceOrderItem` does not change.** Its "does not create a StockMovement" example stops being a known gap and becomes the rule: an undelivered line has no net stock out.

**S9. The product page names the note.** For an `OrderItem` reference the movement list prints **"Nota \<paper_number\>"** (`movement.reference.order.paper_number`); the `Order` and `Invoice` branches stay. One line in an existing list — no wireframe (the owner was told and did not object).

**S10. Fixtures seed stock through movements.** Any spec that asserts on stock starts its products at 0 and adds stock with a `purchase` movement (`create(:stock_movement, …)` + `recalculate_current_stock!`), never with `current_stock:` alone. Existing `create_order_spec` examples that only need "a product" keep the factory; the ones that assert on stock move to movements.

**S11. Nothing else moves.** `Product.with_low_stock`, the dashboard's "Stock Bajo" and the product page's number simply become true. Average cost stays out (part 1's D1). No UI changes beyond S9.

## Cutover

Unchanged from part 1: the baseline is the ledger. `Inventory::SyncFromCsv` and the seeds write stock as movements; a product whose `current_stock` was edited outside those paths would lose its baseline at its first movement — the owner spot-checks before go-live. Historical sales are not backfilled; after go-live the count may read high for products sold before it, and the existing per-product adjustment corrects them.

## Backend

### `app/models/stock_movement.rb`
`validates :reference_type, inclusion: { in: %w[Order Invoice OrderItem] }, if: -> { reference_id.present? }`.

### `app/models/order_item.rb`
`has_many :stock_movements, as: :reference, dependent: :nullify`.

### `app/models/order.rb`
```ruby
def sale_movements
  StockMovement.where(reference_type: "OrderItem", reference_id: order_items.select(:id))
end
```

### `app/services/inventory/deduct_line_stock.rb`, `restore_line_stock.rb` — S4.

### `app/services/sales/create_order.rb` — S5.

### `app/services/inventory/mark_delivered.rb` — S6.

### `app/services/sales/cancel_order.rb` — S7.

### `app/views/web/products/show.html.haml` — S9 (the `@recent_movements` list is ten rows; the two extra reads per `OrderItem` row are accepted).

## Element mapping (audit result)

| Element | Status | Backing |
|---|---|---|
| `Order has_many :stock_movements, as: :reference`; `OrderItem belongs_to :product, -> { with_deleted }` | exists | models |
| `OrderItem` as a `StockMovement` reference | new, model | inclusion value + `has_many`; no migration |
| `Order#sale_movements` | new, one method | model |
| Floor-at-zero deduction, net restore | new, two services | `Inventory::AdjustStock`, `StockLocation.first!` |
| `CreateOrder` deducting per line; `live` block removed | new | service; existing "insufficient stock" examples rewritten |
| `MarkDelivered` per line, transactional, idempotent, deduct/restore | new | service; controller and policy unchanged |
| `CancelOrder` restoring lines with cash in one transaction | new | service; dormant examples rewritten |
| `ReplaceOrderItem` untouched | exists | its no-movement example becomes the rule |
| Product page "Nota N" label | new, view | `movement.reference.order.paper_number` |
| Dashboard / low-stock reads | exists | unchanged |
| `WORKING_CONTEXT`, `DEVELOPMENT_GUIDE`, `TESTING_GUIDE` | new, docs | — |

No conflicts with: the stock mutation rule (every write through `AdjustStock`), `Result`, thin controllers (no controller changes), Pundit (no policy changes), HAML-only, `UI_DESIGN_SPEC` (one text label). The July spec's D is superseded on purpose and recorded as such.

## Edge cases

- **Same product twice in one order** (the form merges them, the service must not assume it): sequential deductions with a fresh read; the second sees what the first left.
- **Delivery undone after part of the stock was sold elsewhere**: a restore is an add-back and never needs a floor.
- **Cancel an on_account with lines delivered, undone and re-delivered**: the net per line is what comes back.
- **Cancel when the cash reversal fails** (a payment already reversed): stock, status and allocations all roll back.
- **Cancel an immediate sale whose product was soft-deleted**: `OrderItem belongs_to :product, -> { with_deleted }` — the restore still runs.
- **A line deducted 0 (nothing on the shelf)**: no movement; cancel and undo give nothing back; the order still cancels.
- **`delivered_product_ids` naming a product not in the items**: ignored, as today.
- **No `StockLocation`**: `first!` raises inside the transaction → the sale/delivery/cancel fails whole; seeds and specs create one.

## Constraints (binding; the plan copies them into Global Constraints)

- Stock is never written directly; only `Inventory::AdjustStock` → `StockMovement` → `Product#recalculate_current_stock!`. Every spec that moves stock creates a `StockLocation` and seeds stock through movements (S10).
- Services return `Result`; controllers stay thin (none change here); Pundit untouched; HAML only; no logic in views beyond S9's label.
- Code, comments and specs in English; comments minimal; no references to AGENTS.md or any doctrine document in code or specs. Movement notes and any new user-facing message in Spanish; the existing English `ValidationError` messages of `CreateOrder`/`CancelOrder` stay.
- Reuse before writing: `Inventory::AdjustStock`, the `Result` pattern, the existing `:stock_movement` factory.
- One commit per task, `type(feat_34): title`, body in bullets, no attribution lines; the owner squashes both parts together.
- Subagents only when the owner asks, as `builder` / `reviewer`.

## Testing

- **`Inventory::DeductLineStock`**: 3→2 leaves 1 with a `-2` sale movement referencing the line; 3→5 leaves 0 with `-3`; 0→5 writes nothing and succeeds; the movement carries the note and `StockLocation.first!`.
- **`Inventory::RestoreLineStock`**: after a `-3` sale, restores `+3` as an `adjustment` referencing the line; after `-3`/`+3`/`-3`, restores 3; with no movements, writes nothing; after a 0-deduction, writes nothing.
- **`Sales::CreateOrder`**: immediate and credit deduct every line (the three floor cases, seeded through movements); on_account deducts only the delivered lines; the same product on two lines deducts in sequence; a failed deduction rolls back order, lines and movements; the "insufficient stock" context becomes "sells past the count, floored at zero" for `live` too; `from_paper` behaves identically.
- **`Inventory::MarkDelivered`**: delivering deducts and stamps; delivering an already delivered line does nothing twice; `delivered: false` restores and clears; a failed movement leaves `delivered_at` untouched; the existing "ignores foreign ids" and "rejects non on_account" stay; the "does not create a StockMovement" example flips to "creates the sale movement".
- **`Sales::CancelOrder`**: the three dormant examples rewritten to net restores (immediate: `+5` adjustment referencing the line; multi-item; the `reason` note); an on_account with one of two lines delivered gives back that one only; a cancelled order whose line took 0 gives nothing back; cash and stock roll back together when `Cash::ReversePayment` fails (the existing example gains a stock assertion); the existing `xit` rollback example is enabled with `Inventory::AdjustStock` stubbed.
- **`Sales::ReplaceOrderItem`**: its no-movement example stays, on a line that was never delivered.
- **Request**: `POST /web/payments_on_account/:id/deliver` with ids drops the products' stock; `GET /web/products/:id` shows "Nota \<paper_number\>" for a sale movement.
- Nothing asserts on a factory `current_stock:` that has no movement behind it.

## Out of scope

Dropping `source` / `from_paper`, `max_stock` and `Inventory::SyncFromCsv` (cleanup work-item with a migration); average cost; an undo-delivery button (the service supports it, no screen asks for it); backfilling historical sales; choosing a stock location.

## WORKING_CONTEXT.md updates (after implementation)

- **Orders**: sales now write `sale` movements at creation (immediate, credit) or at delivery (on_account), floored at zero; `CreateOrder` never refuses a sale for stock; `source`/`from_paper` no longer gate anything.
- **Payments on account**: `delivered_at` is the stock event; `MarkDelivered` deducts/restores per line, idempotent, transactional; `ReplaceOrderItem` moves no stock because it only touches undelivered lines.
- **Stock**: movements of a sale reference the `OrderItem`; `Order#sale_movements`; cancel restores each line's net through `Inventory::RestoreLineStock`, with cash, in one transaction.
- **Key constraints**: the floor; stock never gates a sale; restore = the line's net.
- **Active services**: `Inventory::DeductLineStock`, `Inventory::RestoreLineStock`.
- Remove the "stock is not modified when selling" and "no sale movement is created" statements.
