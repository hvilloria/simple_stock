# Invoice and credit note list filters — design

Date: 2026-07-26
Branch: `feat_26-invoice-credit-note-filters`
Scope: `web/invoices#index`, `web/credit_notes#index`

## Problem

`feat_25` turned `web/orders#index` into a filterable history. The two supplier-side
lists were left out and carry the same defects.

**Invoices.** The list is ordered by `priority_order`: pending first, then nearest
due date. That is a worklist ordering — correct while the question is "what do I
owe". There is no way to ask "what did I pay". Ordering paid invoices by due date
is meaningless: an invoice due in March and paid today sorts above one due in
August and paid a month ago.

**Credit notes.** The status filter offers three options and two of them are dead:
the select submits `"pending"` and `"applied"`, but the enum only defines `active`
and `cancelled`, so both return zero rows. The list is capped at `.limit(50)` with
no pagination, and the metrics are computed on that truncated relation, so the
totals are wrong past 50 notes.

Both screens wrap their content in a turbo frame while the filter form sits
outside targeting it — the pattern that broke during `feat_25`. Two live symptoms:
the "Limpiar" button never re-renders (it lags one request behind), and the frame
does not advance the URL, so reloading or sharing a link loses every filter.

## Invoices

### Date axis follows state

`paid_at` already exists, is indexed, and is stamped by `Invoice#mark_as_paid!`,
which both payment paths go through — the single invoice action and the bulk
`Invoices::ProcessPayment`. It holds the payment date chosen by the operator, not
the timestamp of the click. **No migration and no backfill are needed.**

The status filter selects which date column is shown and sorted:

| Status     | Column header | Sorted by                       |
| ---------- | ------------- | ------------------------------- |
| Pendientes | Vencimiento   | `priority_order` (due date asc) |
| Pagadas    | Pagada el     | `paid_at DESC`                  |
| Canceladas | Vencimiento   | `priority_order`                |

The list keeps its separate purchase-date column untouched; only the second date
column follows the axis. The "¡Vencida!" and "Vence en N días" sub-labels render
only under Pendientes — on a paid or cancelled invoice they mean nothing.

### Filter

Three mutually exclusive options, no "Todas": **Pendientes** (default), **Pagadas**,
**Canceladas**. Cancelled invoices need their own option because with an exclusive
filter they would otherwise vanish from the screen entirely, and `#cancel`
redirects to this very index.

### Model changes

```ruby
scope :by_status_filter, ->(status) { where(status: status) if statuses.key?(status.to_s) }
scope :by_payment_date, -> { order(Arel.sql("paid_at DESC NULLS LAST"), id: :desc) }
```

`by_status_filter` ignores out-of-domain values, so `?status=<anything>` cannot
raise or silently widen the list. `NULLS LAST` is defensive: every current write
path stamps `paid_at`, but a legacy row without it must fall to the bottom rather
than head the list.

`priority_order` gains an `id DESC` tiebreaker. Without it, invoices sharing a due
date can repeat on one page and disappear from another under pagination.

### Controller

`@status` comes from `params[:status]`, defaults to `"pending"`, and coerces
anything out of domain back to `"pending"`.

```ruby
invoices_scope = Invoice.simple_mode
                        .includes(:supplier)
                        .for_supplier(@selected_supplier)
                        .search_invoice(params[:invoice_search])
                        .by_status_filter(@status)

ordered = @status == "paid" ? invoices_scope.by_payment_date : invoices_scope.priority_order
@pagy, @invoices = pagy(ordered)
```

### View

The `turbo_frame_tag` wrapper and the form's `turbo_frame:` target are removed —
plain navigation, filters travel in the URL. The status select joins the existing
form next to the supplier select.

Two existing defects the new filter would otherwise aggravate:

- The empty state reads "No hay facturas registradas / Comenzá registrando la
  primera". With filters active that is false — there are invoices, just not
  these. It becomes a filtered empty state with a clear-filters link.
- The "Limpiar" button's visibility now also accounts for a non-default status.

### Unchanged

The three metric cards keep computing over `pending_payment`, independent of the
status filter. "Deuda Total Pendiente" is a global business figure; making it
change because the operator is browsing paid history would make it useless. They
keep honouring supplier and search, as today.

No period filter. Sales needed one because the volume is daily; here the volume is
far lower and pagination plus number search cover it. It can be added on this
skeleton later if it turns out to be needed.

## Credit notes

### The status filter is not the enum

"Disponibles" and "Aplicadas" are not stored states — they are the same `active`
row with and without balance, and the balance is not a column: it is
`amount - applied_credits.sum(:amount)`.

| Option      | Means                            |
| ----------- | -------------------------------- |
| Disponibles | `status = active` and balance > 0 |
| Aplicadas   | `status = active` and balance = 0 |
| Canceladas  | `status = cancelled`             |

### Model changes

The balance moves into SQL through a correlated subquery, so that filtering and
pagination operate on the same set:

```ruby
scope :with_balance, -> {
  where("credit_notes.amount > COALESCE((SELECT SUM(ac.amount) FROM applied_credits ac WHERE ac.credit_note_id = credit_notes.id), 0)")
}
scope :exhausted_credits, -> {
  where("credit_notes.amount <= COALESCE((SELECT SUM(ac.amount) FROM applied_credits ac WHERE ac.credit_note_id = credit_notes.id), 0)")
}
scope :by_availability, ->(filter) {
  case filter
  when "available" then where(status: "active").with_balance
  when "applied"   then where(status: "active").exhausted_credits
  when "cancelled" then where(status: "cancelled")
  end
}
```

Any other value — including a blank one — returns the scope untouched, which is
the "Todos los estados" case. The current `by_status` scope is left unused and
removed.

`recent` gains an `id: :desc` tiebreaker. It matters more here than in invoices:
`issue_date` is a date without time, and several notes sharing a day is normal.

### No axis switch here

A `credit_notes.applied_at` column exists but nothing writes it — the real
application date lives in `applied_credits.applied_at`, and a note may be applied
in several instalments. Ordering "Aplicadas" by application date would require
choosing which of them and pulling it out of the join. Out of scope; the list is
ordered by issue date throughout.

### Controller

`pagy` replaces `.limit(50)`, with `includes(:supplier, :invoice, :applied_credits)`.
Without that last one, computing each row's balance fires one query per note.

Metrics move to their own unpaginated scope, excluding the status filter: the
available credit for the current supplier and search. Same rationale as the
invoice cards, and it is what fixes the number — today it sums only the first 50
rows, and under `pagy` it would sum 20.

### View

Turbo frame removed, select values corrected, pagination block added matching
invoices and sales, and the empty state gains the status case.

## Tests

Neither `spec/requests/web/invoices_spec.rb` nor `spec/requests/web/credit_notes_spec.rb`
exists — only `invoices_pending_credits_spec.rb`. Both are created.

- Each status returns exactly its own set, and an invalid `?status=` falls back to
  the default without raising.
- Under Pagadas, an old invoice paid today sorts **above** a newer one paid last
  week. This is the flagship example: reverting the axis change must fail it.
- The `id` tiebreaker in both models: rows sharing a date neither repeat nor
  disappear across pages.
- "Disponibles" and "Aplicadas" return rows. These fail against the current code
  and pass with the fix.
- The credit metric does not depend on the page: with more notes than fit on one
  page, the total is still the total.

Examples that depend on the weekday or the month anchor their dates with
`travel_to`.
