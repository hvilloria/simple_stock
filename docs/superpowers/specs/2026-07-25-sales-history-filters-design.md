# Sales history with filters (`web/orders#index`) — feat_25

Date: 2026-07-25
Branch: `feat_25-sales-history-filters`
Commit scope: `feat(feat_25): …`

## Problem

`Web::OrdersController#index` lists every order sorted by `sale_date DESC` with a
hard `limit(50)` and no filters. The moment an order was collected is not recorded
anywhere: it only exists implicitly as the `payment_date` of the payments allocated
to it.

Consequence: an `on_account` order created five days ago and collected today is
buried behind orders created more recently. The operator collects a sale, opens
Ventas to check it, and cannot find it. The same class of problem exists in
`invoices#index` and `credit_notes#index`, deliberately left out of this feature.

## Scope

In scope: `web/orders#index` only, plus the schema and model changes that feed it.

Out of scope:

- `invoices#index` and `credit_notes#index` — same criteria, separate feature.
  Neither needs a migration (`invoices.paid_at` already exists; credit notes can
  derive the applied date from `applied_credits`).
- The three collection screens (`web/sale_notes`, `web/payments_on_account`,
  `web/customers/debtors`). They are the open-work queues, one per order type,
  and this screen does not compete with them.
- An index of partial payments. Orders with a partial payment have no
  `settled_on` and therefore never appear on the collected axis; that screen does
  not exist yet.
- `web/orders/show` renders the order type with only two branches (`immediate` →
  "Contado", anything else → "Cuenta Corriente"), so an `on_account` order is
  mislabelled there. Pre-existing bug, noted but not fixed here.

## Framing

The screen answers one question: *what happened?* It is a global history, not a
work queue. The date axis and the state filter are not independent — the
collected date only exists for collected orders — so **the state selects the
axis**, and the date column is relabelled accordingly. This removes the trap
where filtering by a collected date silently drops every uncollected row.

## Data model

New column `orders.settled_on` — `date`, indexed, nullable.

- Value: `MAX(payments.payment_date)` across the order's `payment_allocations`.
- Written by `Order#refresh_status_from_balance!` when the balance reaches 0.
  Cleared to `nil` on the inverse transition (`Sales::ReplaceOrderItem` can make a
  confirmed order more expensive and reopen it), and by `Sales::CancelOrder`,
  which clears it whenever a collected order is cancelled.
- The value is derived inside the model. No service signature changes: the four
  existing callers (`Payments::CollectSaleNote`, `Payments::CollectOnAccount`,
  `Payments::AllocatePayment`, `Sales::ReplaceOrderItem`) are untouched.

Two deliberate decisions, recorded because they read like oversights otherwise:

1. **It is the maximum of `payment_date`, not "the payment that closed the
   balance".** An order with a Monday payment that later receives a backdated
   Friday payment is stamped Monday.
2. **`date`, not `datetime`.** The app runs in UTC and dates stored as midnight
   have already caused off-by-one bugs and flaky specs. Intra-day ordering is
   handled by the `id` tiebreaker, which is required anyway.

Why `payment_date` and not `payment_allocations.created_at`: two of the three
collection paths never expose a date field (`CollectSaleNote` and
`CollectOnAccount` always pass `Date.current`), so the two values coincide except
when a credit payment is backdated from `web/customers/:id/payments/new`. In that
case the declared date is the one the operator will search by.

### Backfill

Runs inside the same migration as an `UPDATE`, applying the same expression to
non-cancelled orders whose balance is 0, restricted to rows where `settled_on IS
NULL` so it is re-runnable.

Without it the screen opens empty on day one: every historical order would have a
`NULL` collected date and disappear from the default filter.

The backfill lives in the migration and nowhere else. It is not extracted into a
rake task or a model method: migrations must not depend on application code that
may change later, and a repair script for a problem that has not happened yet is
speculative.

## Query

New scopes on `Order` — the filters live in the model, the controller only chains
them. Each is a no-op when its parameter is blank, matching `Invoice.for_supplier`.

| Scope | Behavior |
|---|---|
| `by_type(t)` | filters `order_type` |
| `by_status_filter(s)` | Cobradas → `confirmed`, Pendientes → `pending`, Anuladas → `cancelled`; blank or "Todas" does not filter |
| `settled_between(from, to)` | range on `settled_on` |
| `sold_between(from, to)` | range on `sale_date` |
| `search_paper(q)` | `ILIKE` on `paper_number` |

`#index` has two explicit branches:

**Search mode** (`paper_number` present): `Order.search_paper(q)` over the whole
history. Type, status and period are ignored, including their defaults. Ordered
by `sale_date DESC, id DESC`.

**Filter mode**: type + status + period chained, with the status selecting the axis.

| Status filter | Period applies to | Order | Date column |
|---|---|---|---|
| Cobradas (default) | `settled_on` | `settled_on DESC NULLS LAST, id DESC` | "Cobrada el" |
| Pendientes | `sale_date` | `sale_date DESC, id DESC` | "Fecha venta" |
| Anuladas | `sale_date` | `sale_date DESC, id DESC` | "Fecha venta" |
| Todas | not applied | `sale_date DESC, id DESC` | "Fecha venta" + informational "Cobrada el" |

Todas ignores the period entirely and renders the Período select `disabled` — the
same gesture search mode already uses. Forcing a date range onto the one mode
whose purpose is *not* to narrow produces a confusing result: an order sold last
month but collected today is visible under Cobradas · Esta semana and disappears
the moment the operator switches to Todas, because the axis silently moves to
`sale_date`. Dropping the period there removes the problem instead of patching it.

Ordering falls back to `sale_date` rather than `id` because `sale_date` is the one
date every order has regardless of state, and it is the column on screen — sorting
by insertion order would leave the list looking unordered.

Tipo still applies under Todas; it is orthogonal to state.

The `id` tiebreaker is mandatory on every branch. Both dates are `date` columns,
so ties within a day are common, and an unstable sort combined with pagination
makes rows repeat across pages or vanish entirely.

`NULLS LAST` is not what protects a confirmed order with no collected date
from disappearing: `settled_between` filters by range and drops `NULL` rows
before ordering ever runs. `NULLS LAST` only orders such a row last when no
period narrows the list.

Pagination uses pagy, which the project already defaults to 20 per page
(`Pagy::DEFAULT[:items]`), replacing the current `limit(50)`. The existing
`includes(:customer, order_items: :product)` stays — `:user` is dropped since
the Vendedor column was removed — each row still sums item quantities, and
without the `includes` the list is N+1 per row.

No metrics or totals: the operator uses this screen to locate a specific sale,
not to reconcile a period. One listing query and one count per request.

## View

Layout follows `web/invoices/index`: title and "Nueva Venta" action, a filter
card, and the table and pagination below it, all on the same full-page
navigation. There is no `turbo_frame`: the filter card holds request-dependent
content (the disabled selects, the search notice) and sits outside any frame,
so a frame-targeted submit would leave it stale.

**Two independent GET forms** inside the filter card. The search input submits
only `paper_number`; the three selects submit type, status and period. Because
each form carries its own parameters, entering search mode does not need to clear
the others — they simply never travel in the URL. No new JavaScript: auto-submit
reuses the existing `filter-form` Stimulus controller (`change->submit` on
selects, `input->submitWithDebounce` on the text field).

**Rango was removed after implementation** (2026-07-26): it was the only
control on the screen needing two values to mean anything, and every
complication traced back to it — a silently unfiltered list when one bound
was set, then required fields that trapped the operator inside the mode.
Finding an older sale is already served by the paper-number search, which
sweeps the whole history regardless of filters. Do not reintroduce it without
a concrete use case the search does not already cover.

The search input carries `autofocus` while a search is active, because the
full-page navigation would otherwise drop the caret.

Filter controls and their defaults:

| Control | Values | Default |
|---|---|---|
| Buscar | free text over `paper_number` | empty |
| Tipo | Todos los tipos · Notas de pedido · Pagos a cuenta · Cuenta corriente | Todos los tipos |
| Estado | Todas · Cobradas · Pendientes · Anuladas | Cobradas |
| Período | Hoy · Esta semana · Este mes | Esta semana |

The period applies to whichever axis the status selects, never to both, and does
not apply at all under Todas. "Esta semana" and "Este mes" follow the calendar,
matching the existing `Invoice` period scopes (week starts Monday).

### Table columns

Productos · date column (per axis, above) · **Tipo** (new) · Cliente · Estado ·
Total · Acciones.

The **Vendedor** column is removed. With Tipo added the table reached eight
columns; the seller is still visible on the order detail. This is a deliberate
removal, not an omission.

### States

| State | Behavior |
|---|---|
| Populated | As above. |
| Empty with filters | "No hay ventas con esos filtros" plus a Limpiar action. This is the only empty state: defaults are always applied (Cobradas · Esta semana), so a generic "no sales yet" screen is unreachable. |
| Search mode | The three selects render visible but `disabled`, with a line stating the search runs over the whole history ignoring filters, and a "Limpiar búsqueda" escape. The table adds "Cobrada el" as an informational column ("—" when not collected). |

Clearing returns to the defaults: Cobradas · Esta semana.

### Vocabulary

Type filter labels: **Notas de pedido** (`immediate`), **Pagos a cuenta**
(`on_account`), **Cuenta corriente** (`credit`). "Notas de pedido" matches the
sidebar and the cashier screen where these orders are collected. The radio button
in `web/orders/new` still says "Contado"; unifying that is out of scope.

The status badge is renamed from **"Confirmada"** to **"Cobrada"** in
`orders/index` and `orders/show`, so the filter and the rows use the same word.
Filtering by "Cobradas" and seeing rows labelled "Confirmada" is the kind of
mismatch that makes an operator distrust the filter.

### Authorization

`OrderPolicy#index?` is `true` for all three roles, so the screen itself needs no
change.

The Cancelar button is currently rendered for every non-cancelled order without
consulting the policy; the block happens on click, via a Pundit redirect. With
the default filter set to Cobradas, caja and vendedor users would see a dead
button on every single row. The button is therefore gated with
`policy(order).cancel_pending?` / `cancel?` in this feature — a two-line change
directly caused by it.

## Element mapping

**Exists, reused:** filter card and auto-submit (`filter-form`), pagy,
`order_type` and `status` enums with their scopes, `paper_number` (indexed
column), empty-state pattern, Cancelar action and its policies, `includes` for
N+1.

**New:** `settled_on` migration and backfill, stamping and clearing in
`refresh_status_from_balance!`, the five scopes above, the Tipo column, the
search-mode branch and its notice, the badge rename, the Pundit gate on
Cancelar.

## Testing

Money flow, so request specs are required in addition to unit specs.

**Unit (`spec/models/order_spec.rb`)**

- Collecting in full stamps the payment date.
- A reopening swap clears it.
- Closing again re-stamps with the new date.
- It is the maximum `payment_date`, not the most recently loaded payment.
- A cancelled order is left without a date.
- Each filter scope is a no-op with a blank parameter; ranges include their bounds.

**Request (`spec/requests/web/orders_spec.rb`)**

- Each status value produces the correct ordering axis. The core case: an order
  created days ago and collected today comes first under Cobradas.
- Search mode ignores type, status and period, including their defaults.
- A filter combination with no matches renders the empty state.
- Page 2 neither repeats nor skips rows — the case that justifies the `id`
  tiebreaker.
- An unrecognised period value falls back to the default.
- The type filter narrows the list: filtering by Pagos a cuenta drops
  `immediate` and `credit` orders.
- Todas ignores the period: an order sold outside the selected period still
  appears. This is the case that made the period disappear from that mode.
- Under Todas and in search mode the informational "Cobrada el" column renders,
  showing a dash for orders that were never collected.
- The Cancelar button is gated by role: an admin sees it on a collected order,
  caja and vendedor do not. This pins a permissions regression that fails
  silently — a view refactor that drops the policy call brings the dead button
  back with no other symptom.

**Backfill:** a spec proving orders collected before the migration appear under
Cobradas with the correct date. It is the only test that verifies the screen does
not open empty on day one.

**System:** none. The interaction is the existing `filter-form` auto-submit,
already covered through Facturas. No new JavaScript ships with this feature.

## Constraints

Binding rules for anyone implementing this. They come from standing user
preferences and are not negotiable defaults.

- **Reuse before writing.** `filter-form`, the pagy block, the invoices filter
  card and the empty-state pattern already exist. Do not introduce new Stimulus
  controllers, helpers or partials where these cover the need.
- **UI stays sober.** `docs/UI_DESIGN_SPEC.md`: slate base, white cards, subtle
  borders. Semantic colors carry meaning only, never decoration.
- **The UI shows the operator's mental model,** not persistence details. The
  collected date is "Cobrada el"; that it derives from a maximum over payments
  never surfaces.
- **UI text in Spanish; code, comments and commit messages in English.**
- **Minimal comments in code.** Only non-obvious "why". No comments that
  cross-reference doctrine documents — every file must stand on its own.
- **One commit for the whole feature,** authored by the user. Do not run
  `git add` or `git commit`; hand over the message. No attribution or
  co-author trailers.
- **Timezone:** `Date.current` / `Time.current` only, never `Date.today`.
- **Stock rule** is untouched here: this feature creates no stock movements.

## Wireframes

Rendered in the brainstorming visual companion at
`.superpowers/brainstorm/75394-1785030218/content/orders-index.html`
(gitignored; regenerate if needed). Four states were reviewed and approved:
populated, search mode (variant A — filters visible but disabled), empty with
filters, and invalid range.

Approved decisions from that review: variant A for search mode, and removal of
the Vendedor column.
