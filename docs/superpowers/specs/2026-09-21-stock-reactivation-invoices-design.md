# Stock reactivation, part 1: invoices with products — Design

**Status:** design approved by the owner on 2026-09-21 (direction, then wireframes).
**Branch:** `feat-34_stock-reactivation`, commit scope `feat_34`.
**Builds on:** `2026-07-09-invoice-items-stock-reactivation-design.md` — the July
design, twelve decisions locked after review, never implemented. This document
revalidates it against the code as it is today and carries the invoice half to
the point where a plan can be written. The sales half (orders decrementing
stock, cancel reversing it) is part 2 and gets its own design pass; the cleanup
work-item that removes `source`/`from_paper` stays a separate change.

## Goal

A supplier invoice can carry its products. When it does, registering it
**adds their quantities to stock** and its total is **computed from the
lines**; when it does not, it is exactly the amount-only invoice the shop
registers today. Either way it enters accounts payable unchanged. Cancelling an
invoice that moved stock takes back what it added, as far as there is stock to
take.

## The July design, revalidated

Every decision was checked against `main` at `2e4efa1` and later. None is
invalidated; the invoice side of the codebase did not move since July. What did
move is recorded here so nobody re-derives it.

| Decision | Verdict | What the code shows today |
|---|---|---|
| A — one flow, lines optional, `amount = Σ`, `has_items: false` | holds | `Invoice#total_amount` returns `amount` when `has_items` is false; `Invoice.simple_mode` and `InvoicePolicy#mark_as_paid?` both key on `has_items: false`, so an itemized invoice stored this way flows through pending, mark-as-paid, early-payment discount and credit notes untouched. `total_cost` exists as a column but belongs to the dormant full mode; this feature never writes it. |
| B — `amount` frozen on edit when items exist | holds | `Web::InvoicesController#update` permits `:amount` and `edit.html.haml` renders it as an input; both change. |
| C, D (sales side) | deferred to part 2 | `Sales::CancelOrder` now also reverses **cash** (`Cash::ReversePayment`) since the cash module; enabling stock reversal there touches a method that already moves money. Out of this part. |
| D (invoice cancel) | holds | `Invoice has_many :stock_movements, as: :reference` exists, so "the actual purchase movements of this invoice" is `invoice.stock_movements.where(movement_type: "purchase")`. |
| E — `Invoices::CancelInvoice` | holds | Cancel is still `@invoice.update(status: "cancelled")` in the controller, and it has **no request spec at all** — only the index filter by `cancelled` is covered. |
| F — average cost out of v1 | holds, re-confirmed by the owner | `Product#recalculate_average_cost!` aggregates only `confirmed` invoices; these are born `pending`. `docs/DEVELOPMENT_GUIDE.md` says purchases "must recalculate weighted average cost" — that line gets an honest note, not silent disagreement. |
| G — zero-total itemized allowed | holds; the landmine is real | `validates :amount, numericality: { greater_than: 0 }, if: -> { !has_items? && amount.present? }` cannot tell an itemized-but-simple invoice apart. The guard must key on the presence of items, and the service must **build** the items before `save!` so the guard sees them (`Purchasing::CreatePurchase` creates them after, which would not work). |
| H — `Invoices::CreateInvoice` absorbs `CreateSimpleInvoice` | holds | `CreateSimpleInvoice` returns `errors: [ e.record.errors.full_messages ]` — nested, which `join` happens to hide but any other consumer would not — and is not transactional. Its callers are `Web::InvoicesController#create`, `db/seeds.rb` (twice) and its spec. |
| 8 — soft-delete interaction | holds | `InvoiceItem belongs_to :product, -> { with_deleted }` and `StockMovement belongs_to :product, -> { with_deleted }` are in; `Product has_many :stock_movements` has no `dependent: :destroy`. Nothing to add. |
| 9 — single `StockLocation.first!` | holds | Every caller uses it; `spec/factories/stock_locations.rb` exists. |
| Form copy is false once lines exist | holds | `new.html.haml` still renders "Modo Simple … El stock NO se actualiza" and the "Qué NO hace este registro" list. |

New since July, relevant to this part:

- `product-search` (`app/javascript/controllers/product_search_controller.js`) is
  the reusable searcher: it fetches `search_web_products_path` (`Product.active
  .search(q).limit(10)`, paranoid default scope hides soft-deleted rows,
  `ProductPolicy#search?` is true for everyone) and dispatches
  `product-selected` with the product JSON (`id, sku, name, price_unit,
  current_stock, brand, origin, product_type`). Its result rows **dim products
  with zero stock** — right for selling, wrong for buying.
- `invoice_form_controller.js` owns the header: AR amount formatting, due-date
  and early-payment computation, the summary panel, the exchange-rate toggle.
- The order form (`order_form_controller.js`) is the precedent for a
  client-side line table: hidden `purchase_items[N][…]` inputs, `renderItems`,
  `parseAmount`/`formatAmount`, and an `initialItems` value that re-renders
  lines after a failed submit.

## Decisions taken now

**D1. Average cost stays out.** Owner's call on 2026-09-21, against the option
of recalculating on registration. `cost_unit` is untouched; the line's
`unit_cost` is persisted, so the average can be computed later without losing
data. `DEVELOPMENT_GUIDE.md`'s "must recalculate weighted average cost" gains a
note that it is deferred.

**D2. The Productos card is always visible.** No "with products?" toggle, no
mode to choose: it is the same form with one more card, between "Información de
la Factura" and "Notas Adicionales". Empty it says, in one line, what adding
products does.

**D3. What counts as a line: a product AND a quantity greater than zero.**
A row with no quantity (blank or 0) is incomplete: shown dimmed, subtotal "—",
counted nowhere, moving nothing, and it does not block submitting. **A blank
unit cost is a cost of 0, not an incomplete row:** the input shows `0,00` on
blur, the line counts, moves its stock and adds nothing to the total. Same
rule in the front end and in the service; the server is authoritative and
never sends a zero quantity to `Inventory::AdjustStock`, which would reject
it. A line that was forgotten cannot silently drop out of the invoice; a cost
that was forgotten cannot silently pass — that is D13's job.

**D13. Zero-cost lines get a second look, and only they do.** When at least
one complete line has a unit cost of 0, submitting opens a confirmation modal
before the POST. The owner chose this over confirming every itemized invoice
so that the modal's appearance itself says "something unusual here". It names
the lines ("2 líneas con costo 0: Filtro de aire Corolla ×1, …"), restates
what will happen ("Se suman N unidades en M productos"), and offers
**Registrar** (primary) and **Volver a revisar** (secondary). The legitimate
case is a warranty replacement or a supplier bonus; the modal is where a
forgotten cost gets caught. Amount-only invoices and itemized invoices with
every cost above 0 never see it.

**D14. The early-payment discount is untouched, and it applies to the
computed total.** The supplier's discount is a percentage of `amount`, applied
when the invoice is paid (`Invoice#amount_with_discount`,
`eligible_for_discount?`, `Invoices::MarkAsPaid` marking `paid_with_discount`),
and `set_early_payment_terms` still fills the terms from the supplier on
create. With lines, `amount = Σ`, so the discount lands on the sum exactly as
it lands on a typed amount — it is financial, never a change to a line's
`unit_cost` and never a stock matter. In the form, the frozen amount is
written into the **same** `amount` input `invoice_form_controller#updateSummary`
already reads, and that method is called after every lines change, so
"Monto final" under "Con descuento anticipado" recomputes with no new logic.
The early-payment card keeps its place between the invoice info and the
products.

**D4. The amount freezes, it does not disappear.** With at least one complete
line, "Monto Total" is read-only and mirrors the sum, with a caption saying so.
Removing the last complete line makes it editable again with whatever value it
had. The client displays; **the server recomputes and ignores the submitted
amount when lines are present**.

**D5. Unit cost is in the invoice's currency**, and the column header follows
the currency radio (`US$` / `$`). Formatting through `currency-input`, like
every amount in the app.

**D6. Picking a product adds a line with quantity 1, an empty cost, and moves
the focus to the cost** — the one thing the searcher cannot know. The same
product may appear on several lines (two prices on one invoice is real); each
line becomes its own movement.

**D7. The summary says what will happen.** "Sin productos: no mueve stock"
without lines; "Suma stock: N unidades en M productos" with a per-product unit
list otherwise, and the sentence "El costo promedio no cambia" so nobody looks
for it afterwards. The "Modo Simple" block and the "Qué NO hace este registro"
list are removed.

**D8. A failed submit comes back with everything typed.** Today `create` fails
into `Invoice.new` and loses even the header — a due date before the invoice
date, and everything is retyped. With three lines typed that is not
acceptable: on `422` the view re-renders with the header values and the
lines, the flash at the top, and the guilty field marked. The whole write is
one transaction, so a failure leaves zero rows.

**D9. The searcher does not dim out-of-stock products here.** A Stimulus value
on `product-search` (`dimOutOfStock`, default `true`, so the order form is
unchanged) turns the dimming off on the invoice form.

**D10. Show renders the products table only when lines exist**, with the total
and a caption "calculado desde N productos" next to the amount. An amount-only
invoice looks exactly as today. No date on the stock note (the movement date is
the registration, already implied).

**D11. Cancel is a danger button, and its confirmation says what it does to
stock:** "¿Cancelar esta factura? Se descuentan del stock las N unidades que
sumó, hasta donde haya." For an amount-only invoice the text is today's.

**D12. Editing never touches lines.** With lines, `amount` is read-only in the
form and stripped from the permitted params; the lines render read-only with
the sentence "Las líneas no se editan. Si la factura está mal cargada,
cancelala y registrala de nuevo." Every other header field, `exchange_rate`
included, stays editable: the USD amount is fixed and both the invoice's ARS
equivalent and the lines' `subtotal_ars` follow the same rate.

## Wireframes

Rendered as an Artifact (https://claude.ai/artifact/1baTKr7U2xz3MwWR9KUBQJ)
from `.superpowers/mockups/factura-con-productos.html` (gitignored; regenerate
if needed). Five full screens reviewed and approved, grey-box, real labels:

1. Nueva factura, sin productos — populated header, empty Productos card,
   editable amount, summary "Sin productos: no mueve stock".
2. Nueva factura, con productos — three lines, frozen amount mirroring the
   sum, summary with units per product.
3. Error del servidor — `422` with header and lines preserved, flash on top,
   guilty field marked, one incomplete line dimmed and not counted.
4. Ver factura — products table, caption on the amount, danger cancel with the
   stock-aware confirmation.
5. Editar — frozen amount, read-only lines, everything else editable.

6. Confirmación por costo 0 — the D13 modal over the populated form, listing
   the zero-cost lines, with Registrar / Volver a revisar.

Decisions D2, D4, D6, D7, D8, D9, D10, D11, D13, D14 and the "same product twice"
rule in D6 came out of that review. The example invoice is in pesos: USD
registrations are close to none, and the mechanism is the same.

## UI changes

### `web/invoices/new` — the form

- Header cards unchanged (supplier, number, currency, exchange rate, amount,
  dates, early-payment card, notes).
- New card **Productos** (D2): a one-line explanation, the `product-search`
  box, and the lines table — Producto (SKU on its own line, name, brand muted)
  · Cantidad · Costo unit. (`US$`/`$`) · Subtotal · quitar — with a Total
  footer and a "N productos · M unidades" counter in the card header that
  counts complete lines only. Empty state per `UI_DESIGN_SPEC` (short title,
  short explanation, no decoration).
- **Monto Total** freezes per D4, caption "Calculado desde los productos.
  Quitá todas las líneas para escribirlo a mano."
- **Resumen** per D7. Keeps the amount, ARS equivalent, due date and initial
  status lines it has today.
- Lines post as `items[N][product_id]`, `items[N][quantity]`,
  `items[N][unit_cost]` hidden inputs (the order form's `purchase_items`
  shape). Incomplete rows still post; the server ignores them (D3).
- On failure the view receives the submitted header values and the lines as an
  `initialItems` value and re-renders them (D8).
- **Modal "Confirmar registro"** (D13), a partial in the style of the
  "Marcar como Pagada" modal on the show view: title, the zero-cost lines, the
  units sentence, Registrar / Volver a revisar. Hidden until `invoice-form`
  opens it.

### `web/invoices/:id` — show

- Products card below "Información de la Factura", only when
  `invoice.invoice_items.any?`: the same columns read-only, Total footer, and
  "N unidades sumadas al stock" in the card header.
- Caption "calculado desde N productos" beside the amount (D10).
- Cancel: danger button with the D11 confirmation.

### `web/invoices/:id/edit`

- Amount read-only with caption when lines exist; read-only lines card with the
  D12 sentence. Everything else as today.

## Backend

### Service — `Invoices::CreateInvoice` (replaces `Invoices::CreateSimpleInvoice`)

Same keyword interface as today plus `items:` — an array of
`{ product_id:, quantity:, unit_cost: }` hashes, possibly empty, possibly
holding incomplete rows.

- `validate_params` keeps every rule of today's service, with two changes:
  the amount rule becomes "**required and > 0 only when there are no complete
  lines**"; and each complete line must reference an existing product and have
  `unit_cost >= 0`.
- Complete lines are filtered by D3 before anything else.
- One `ActiveRecord::Base.transaction`: build the `Invoice` with
  `status: "pending"`, `has_items: false`; when lines exist, set
  `amount = Σ(quantity × unit_cost)` (server-side, the submitted amount is
  ignored) and **`invoice_items.build`** each line; `save!`; then one
  `Inventory::AdjustStock.call(product:, stock_location: StockLocation.first!,
  movement_type: "purchase", quantity: line.quantity, reference: invoice)` per
  line, raising into the transaction on a `failure?` result.
- Returns `Result` with a **flat** `errors` array: the `Result` contract is
  an array of strings, and today's nested `[ full_messages ]` only works
  because `Array#join` flattens it.
- Callers updated: `Web::InvoicesController#create`, `db/seeds.rb` (two
  calls), the service spec (renamed and extended). `Purchasing::CreatePurchase`
  is left alone: it is the dormant full-mode path, wired to nothing.

### Service — `Invoices::CancelInvoice`

`call(invoice:)` → `Result`. Refuses an already-cancelled invoice. In one
transaction: for each `invoice.stock_movements.where(movement_type: "purchase")`
write a compensating `adjustment` of `-[movement.quantity,
product.current_stock].min` through `Inventory::AdjustStock` (skipping a zero),
then `update!(status: "cancelled")`. An amount-only invoice has no purchase
movements: the loop is empty and only the status changes. The floor means the
default `allow_negative: false` guard never trips; the cancellation always
succeeds. Pattern borrowed from the dormant
`Purchasing::CancelPurchase#reverse_stock_movements`, but reversing **actual
movement rows**, not item quantities.

### Model — `Invoice`

The `amount > 0` guard keys on the presence of items, not on `has_items?`:
required and positive when `!has_items?` **and there are no invoice items**.
With items built in memory before `save!`, the association answers correctly
on a new record; the plan must pin this with a spec (an itemized `amount: 0`
invoice saves; an amount-only `amount: 0` one does not).

### Controller — `Web::InvoicesController`

- `create`: parses `params[:items]` (indexed hash → array; amounts through
  `parse_amount`, quantities `to_i`), calls `Invoices::CreateInvoice`, and on
  failure re-renders `new` instead of building `Invoice.new`: the header
  fields read their default from `params` (the view already uses `*_tag`
  helpers, so `text_field_tag :invoice_number, params[:invoice_number]` is the
  whole change per field) and the lines go back through the `initialItems`
  value (D8).
- `update`: when `@invoice.invoice_items.any?`, `:amount` is removed from the
  permitted params before the update (D12).
- `cancel`: calls `Invoices::CancelInvoice` and redirects with its outcome;
  the `pending`-only guard and `InvoicePolicy#cancel?` stay as they are.

### Stimulus

- **`invoice-lines`** (new): owns the Productos card. Listens to
  `product-selected` from `product-search`, keeps a `lines` array, renders the
  rows with hidden inputs, handles quantity/cost input and remove, computes
  subtotals and the total, applies D3 to decide which rows are complete, and
  dispatches a `lines-changed` event with `{ total, units, products, lines }`.
  Takes an `initialItems` value for D8. Copies the `order_form_controller`
  patterns (`renderItems`, `parseAmount`/`formatAmount`), does not import it.
- **`invoice-form`** (existing): listens to `lines-changed` to freeze/unfreeze
  the amount (D4), update the summary (D7) and the counter; its currency toggle
  also updates the cost column header (D5). Its existing `turbo:submit-start`
  handler (`handleFormSubmit`) gains the D13 step: if any complete line has
  cost 0 and the submit was not already confirmed, cancel the event, fill and
  open the modal; the modal's Registrar sets the confirmed flag and resubmits;
  Volver a revisar closes it.
- **`product-search`** (existing): gains the `dimOutOfStock` value (D9).

### Policy

Unchanged. `create?`, `update?`, `edit?`, `cancel?` are admin-only and
`pending`-only where they already are; `mark_as_paid?` requires
`simple_mode?`, which an itemized invoice satisfies by construction (Decision
A). A paid invoice cannot be cancelled, so the reversal never meets one.

## Element mapping (audit result)

| Element | Status | Backing |
|---|---|---|
| Header fields, early-payment card, notes, summary dates | exists | `new.html.haml`, `invoice_form_controller.js`, service params |
| Product search box + JSON payload | exists | `product_search_controller.js`, `Web::ProductsController#search`, `ProductPolicy#search?` (everyone) |
| Soft-deleted / inactive products excluded from search | exists | `Product.active` + `acts_as_paranoid` default scope |
| No dimming of out-of-stock results on this form | new, small | `dimOutOfStock` value on `product-search` (D9) |
| Lines table, subtotals, total, counter, complete-line rule | new | `invoice-lines` controller, pattern from `order_form_controller` |
| Zero-cost confirmation modal | new, view + small Stimulus | partial after the show view's "Marcar como Pagada" modal; `invoice-form#handleFormSubmit` (D13) |
| Amount freeze/unfreeze, summary copy, cost column currency | new, small | `invoice-form` listening to `lines-changed` |
| Early-payment discount on an itemized invoice | exists | `Invoice#amount_with_discount` over `amount`; `updateSummary` reading the same input (D14) |
| Lines posted as `items[N][…]` | new | hidden inputs, `purchase_items` shape |
| Failed submit keeps header + lines | new | controller passes values back; `initialItems` value (D8) |
| `Invoices::CreateInvoice` (transaction, build-then-save, Σ amount, flat errors) | new, replaces `CreateSimpleInvoice` | callers: controller, seeds ×2, spec |
| Purchase stock movements | exists | `Inventory::AdjustStock` (`movement_type: "purchase"`, `reference: invoice`), `StockLocation.first!` |
| `invoice_items` rows | exists | table + `InvoiceItem` validations (`quantity > 0`, `unit_cost >= 0`, `with_deleted` product) |
| Itemized invoice enters accounts payable | exists | `has_items: false` + `Invoice#total_amount` reading `amount` |
| `amount > 0` guard keyed on items presence | new, model | one condition change + spec |
| `Invoices::CancelInvoice` with floored reversal | new | `invoice.stock_movements` association, `AdjustStock` default guard |
| `cancel` action through the service | new, small | controller |
| Danger cancel button + stock-aware confirmation | new, view | `UI_DESIGN_SPEC` danger button; helper for the units count |
| Show: products table + caption | new, view | `invoice.invoice_items`, `InvoiceItem#subtotal` |
| Edit: frozen amount + read-only lines; `:amount` stripped | new | controller + `edit.html.haml` |
| "Modo Simple" / "Qué NO hace" copy removed | new, view | `new.html.haml` |
| Average cost | out of scope (D1) | `DEVELOPMENT_GUIDE.md` note |
| `WORKING_CONTEXT.md` Invoices / Stock / gaps updated | new, docs | — |

No conflicts with: the stock mutation rule (every movement goes through
`Inventory::AdjustStock` and `recalculate_current_stock!`), the `Result`
pattern, thin controllers, Pundit, HAML-only, `UI_DESIGN_SPEC` (slate base,
danger button only for the destructive action, empty state without
decoration, errors near fields, sticky summary already in use). The one
doctrine tension — `DEVELOPMENT_GUIDE`'s average-cost rule — is resolved by
D1 and recorded rather than hidden.

## Edge cases

- **Itemized invoice summing to 0** (all-free lines): saves, moves stock,
  shows `US$ 0,00`; **amount-only 0**: rejected (Decision G).
- **A due date before the invoice date**, or any other header validation
  failure, with lines typed: `422`, everything preserved, zero rows written
  (D8).
- **Blank unit cost**: becomes 0, shows `0,00`, and triggers the D13 modal on
  submit; a typed 0 behaves the same.
- **Same product on two lines**: two `invoice_items`, two purchase movements.
- **Cancel after part of the goods were sold** (part 2) or adjusted away:
  reversal floored per product at `current_stock`; the cancellation succeeds
  and the invoice's own `purchase` rows remain as history.
- **Cancel an amount-only invoice**: status flip only, today's confirmation
  text.
- **Product soft-deleted after the invoice**: show, edit and cancel still
  render and reverse (`with_deleted` on both associations).
- **Edit changes the exchange rate on an itemized invoice**: allowed; the USD
  amount stays, ARS figures follow.
- **Submitted amount with lines present**: ignored; the server's Σ wins.
- **No `StockLocation`**: `first!` raises inside the transaction → generic
  failure; seeds and every spec that moves stock must create one.

## Constraints (binding; carried into the plan's Global Constraints)

From the project docs:

- Stock is never written directly; only `Inventory::AdjustStock` → `StockMovement`
  → `Product#recalculate_current_stock!` (`CLAUDE.md`, `DEVELOPMENT_GUIDE.md`).
- Services return `Result`; controllers stay thin; Pundit for every action;
  HAML only; no queries or logic in views (`AGENTS.md`, `CODE_PATTERNS.md`).
- **`docs/UI_DESIGN_SPEC.md` governs every view change:** slate base, white
  cards, danger button only for the destructive action, empty states without
  decoration, labels always visible, errors near fields, reuse existing
  partials and patterns before creating new ones, Stimulus only for small
  interaction behaviour.

From the owner's standing feedback (memories the implementers never see):

- **Reuse before writing:** `product-search`, `currency-input`, the
  `parseAmount`/`formatAmount` idiom and the order form's line-table pattern
  are the starting points; no new parser, no new searcher.
- **UI follows the operator's mental model, not persistence:** "una factura
  con productos", never "modo simple / modo full"; `has_items` is never shown.
- **Sober UI per spec:** no saturated accents as decoration; semantic colour
  only where it means something.
- **Full views:** any mockup or screenshot shows the whole screen, never a
  fragment.
- **Comments in code are minimal and in English; no doc cross-references in
  code or specs** (no "see AGENTS.md").
- **One commit per feature, made by the owner:** implementers never run
  `git commit`; they hand back the message.
- **Turbo Streams are new to the project and live only in the cash day
  screen;** this feature does not introduce more of them — the line table is
  Stimulus, like the order form.
- **Stale Tailwind watcher:** if a new class does not render, check
  `app/assets/builds/tailwind.css` before touching markup.
- **Subagents are dispatched only when the owner asks**, as `builder` /
  `reviewer` / `test-runner`.

## Testing

Money and stock both move here, so this is unit + request coverage with
seeded data, plus one browser flow.

- **Characterize before refactoring:** the existing `CreateSimpleInvoice`
  examples (amount-only: typed amount, no items, no movements, early-payment
  terms, every validation) are kept green under the new name **before** the
  itemized path is added.
- **`Invoices::CreateInvoice`, itemized:** stores `amount = Σ`, ignores a
  submitted amount, creates `invoice_items` and one `purchase` movement per
  line raising `current_stock`, `has_items` stays false, appears in
  `Invoice.simple_mode.pending_payment`; incomplete rows are ignored; a zero
  quantity never reaches `AdjustStock`; an all-free invoice saves at 0; a
  header failure after lines rolls everything back (row counts unchanged).
- **Model:** amount-only `amount: 0` invalid; itemized `amount: 0` valid with
  items built in memory.
- **Discount:** an itemized invoice from a supplier with early-payment terms
  gets them set on create and `amount_with_discount` equals `Σ × (1 − pct)`;
  marking it paid with the discount works as for any simple invoice.
- **`Invoices::CancelInvoice`:** floored reversal (received 10, adjusted down
  to 3, cancel restores 0 not −7), amount-only status flip, refuses cancelled,
  every reversal is an `adjustment` row referencing the invoice, the
  invoice's `purchase` rows survive.
- **Request:** `POST /web/invoices` with `items[…]` params (happy path, and a
  `422` that renders the lines back), `PATCH` ignoring `amount` when items
  exist, `POST cancel` reversing stock and refusing a non-pending invoice,
  show rendering the table only with items, the "Modo Simple" copy gone.
- **System (two):** search a product, set cost, watch the amount freeze,
  submit, see stock on the product; and a zero-cost line that opens the modal,
  "Volver a revisar" that closes it without posting, "Registrar" that posts.
- Every spec that moves stock seeds a `StockLocation`.

## Out of scope

- Sales decrementing stock and `Sales::CancelOrder` reversing it (part 2).
- Removing `source` / `from_paper`, `max_stock`, `Inventory::SyncFromCsv`
  (separate cleanup work-item, includes a migration).
- Average cost (D1). Editing lines (D12). Choosing a stock location.
  Backfilling historical stock — the baseline is taken as-is and corrected
  per product through the existing adjustment screen.

## WORKING_CONTEXT.md updates (after implementation)

- **Invoices:** `Invoices::CreateInvoice` (lines optional; `has_items: false`;
  `amount = Σ` when itemized, typed when not; items drive `purchase`
  movements; enters pending-to-pay; `amount` frozen on edit when items
  exist); `Invoices::CancelInvoice` (floored reversal of the actual purchase
  rows). Remove "no stock movements" from the simple-invoice line.
- **Stock:** invoices with lines now write `purchase` movements at
  registration and `adjustment` reversals on cancel. Sales still do not
  (until part 2).
- **Key constraints:** the amount rule keyed on items presence; the
  complete-line rule.
- **Gaps:** average cost deferred; `Purchasing::CreatePurchase` still unwired.
