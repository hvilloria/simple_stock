# Cash module — tramo 4: compensation

The last tramo. Builds on tramos 1, 2 and 3.

Design spec: `docs/CASH_MODULE_DESIGN.md` §3.3 and R-14.

---

## What already works, and what this tramo is actually for

Compensation is **already correct at the data level** and was verified before
this plan was written:

- `Cash::RecordMovement` records a compensation sale with a NULL arca.
- It lands in the drawer zone (it is a sale) and does **not** move the amount to
  wrap.
- It appears in "Ventas por canal".
- It falls out of every reporting group in the balance report, with its own spec.
- The channel select already offers "Compensación", so the cashier can load one.

None of that needs touching. **What is missing is the contact point with
invoices.**

R-14: a supplier we owe takes merchandise from us and the amount comes off the
debt. It counts as a sale for billing, but no money enters any arca. *"That
supplier's debt is adjusted by hand in the invoices module. Cash tells invoices,
never the reverse — the only contact point between the two modules."* Around $4M
across seven months, so not an edge case.

For "cash tells invoices" to mean anything, the movement has to say **which
supplier**. Today it does not — only the free-text description does, and nothing
links a compensation sale to the debt it is supposed to reduce.

**The adjustment stays manual.** Do not create a `CreditNote`, do not touch
`Supplier#current_balance`, do not write anything into the invoices module. Cash
tells; a person acts. That was decided by the owner.

**Branch:** `feat-33_cash-compensation` off the tramo 3 branch. Scope: `feat_33`.

---

## Global constraints

- **`::Cash::Foo` with leading colons** anywhere under `Web::Cash::`.
- Turbo Streams: a list of `turbo_stream.<verb> "<dom-id>"` calls, nothing else;
  every target needs a stable id.
- Partials take locals, never controller ivars.
- Model predicates, not restated conditions — `#sealed?`, `#automatic?`,
  `#transfer?` are read by both the policy and the views, and the row asks
  `policy(movement).update?`.
- Selects that do not apply are **disabled as well as hidden**; hiding alone
  still submits the value.
- **HAML landmine:** it DROPS an attribute whose value is `false`, so a Stimulus
  boolean must be rendered as `x.to_s`.
- **`travel_to Date.new(...) { }` binds the block to `Date.new`.** Use `do...end`.
- `Cash::AmountParser` is the only strict reading of an amount.
- Services return `Result`. HAML only. Code in English, UI strings in Spanish.

---

## Task 1: `cash_movements.supplier_id`

**Files:** migration, `app/models/cash_movement.rb`,
`app/services/cash/record_movement.rb`, factory, specs

A nullable `supplier_id` with a foreign key, used by exactly one thing: naming
the supplier whose debt a compensation sale reduces.

**Validation, following the module's existing conditional pattern** — read
`channel_only_on_sales` and `subcategory_only_on_fixed_expenses` first and match
their shape and their `errors.add(:base, …)` Spanish messages:

- A compensation sale **requires** a supplier. Unlike the invoice type, which
  warns rather than blocks because nobody may know it yet, the cashier recording
  a compensation always knows who took the merchandise — and without it the row
  cannot do the one job it exists for.
- Every other movement must **not** have one.

`Cash::RecordMovement` gains a `supplier:` keyword. Nothing else calls it with
one: no payment method maps to the compensation channel, so
`Cash::RecordSaleFromPayment` and `Cash::ReversePayment` never touch this — say
so in your report after checking, rather than assuming.

Specs: a compensation sale with a supplier is valid; without one it is not; a
cash sale with a supplier is not; the `:compensation_sale` factory trait is
updated so it still builds a valid record.

---

## Task 2: The supplier select on the live row

**Files:** `_live_row.html.haml`, `_edit_row.html.haml`,
`cash_live_row_controller.js`, `movements_controller.rb`, specs

A supplier select in the drawer zone's live row, appearing **only** when the
channel is Compensación — exactly the mechanism the channel and subcategory
selects already use, including being disabled when hidden.

This is the fourth conditional field on that row. Before adding it, read
`toggleFields` and decide whether it still reads clearly with four, or whether it
wants restructuring into a small table of category/channel → visible fields. Say
which you chose. Do not leave four ad-hoc branches if a table is clearer.

The suppliers list must not be a query in the view. Load it in the controller,
and only when it is needed.

Specs: loading a compensation sale from the UI sets the supplier; loading it
without one is refused with the Spanish message; the select does not appear for
other channels and does not submit when hidden.

---

## Task 3: The channel filter and the supplier column in the history

**Files:** `app/services/cash/reports/movements_query.rb`,
`app/views/web/cash/reports/history.html.haml`,
`app/controllers/web/cash/reports_controller.rb`, specs

The history gains a **channel filter** and a **supplier column**.

The channel filter is what makes compensations findable: they have no arca, so
the arca filter cannot reach them, and filtering by category "Venta" returns
every sale of the month. It is also generally useful — filtering by Tarjeta is
how you reconcile against a Payway batch.

The supplier column is blank on every row that is not a compensation.

**WATCH THE QUERY COUNT.** That query costs **four** round trips for a page,
flat, pinned by two specs — one asserting the number and one asserting it does
not change when the page grows from 4 rows to 16. Adding a supplier column must
not make it one per row. If the count changes, update it deliberately, say the
new number, and keep the "does not change as the page grows" example passing —
that is the one that proves the cost is flat.

Note the trap the previous task hit: the cost fixtures contained no transfer, so
the preload was never exercised and the spec would have passed while proving
nothing. **Make sure your fixtures contain a compensation sale with a supplier**,
or the same thing happens again.

Specs: the channel filter narrows correctly and combines with the others; the
supplier shows on a compensation row and is blank elsewhere; the query count.

---

## Task 4: System spec for compensation

**Files:** `spec/system/web/cash_compensation_spec.rb`

The part no request spec sees: choosing Compensación in the channel select
reveals the supplier select, choosing anything else hides **and disables** it,
and a compensation sale saves and appears in the day with no arca and without
moving the amount to wrap.

Follow `spec/system/web/cash_live_row_spec.rb`. Run it three times before
reporting.

---

## Verification for the whole tramo

```
docker compose exec -T web bundle exec rspec
docker compose exec -T web bundle exec rubocop
```

By hand:

1. Load a compensation sale for a supplier. It appears in the day, the amount to
   wrap does not move, and "Ventas por canal" shows it under Compensación.
2. Try to load one without a supplier. Refused, in Spanish.
3. Open the balance report for that period. The sale is in no group — no arca
   received the money, because none did.
4. Open the history, filter by channel Compensación. The month's compensations
   are listed with their suppliers. That list is what the person adjusting the
   debts works from.

---

## What tramo 4 deliberately leaves out

- **Creating the credit note.** The adjustment is manual, in the invoices module.
  Cash tells; a person acts.
- **Touching `Supplier#current_balance`** or anything else in invoices.
- **Tracking whether a compensation has been adjusted yet.** That is a workflow
  the owner has not asked for, and it would need a state nobody maintains.
- **Compensation in the arca zone.** It is a sale; sales live in the drawer zone.
