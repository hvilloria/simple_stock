# Cash module — slice 1c: the collection hook

Builds on 1a (the data foundation) and 1b (the day view and drawer-zone loading).

This slice closes the loop the module exists for: **the cashier stops loading
sales by hand.** Collecting a sale note in the app writes its cash movement by
itself, cancelling a collected sale reverses it, and the day view shows those
rows as something she does not have to touch.

Design spec: `docs/CASH_MODULE_DESIGN.md` §4.1, §4.2, §6.4, §6.5, and rules R-8,
R-10 and R-15.

---

## Environment

No host Ruby — everything runs in Docker. The stack should already be up:

```
docker compose up -d
docker compose exec web bin/rails db:prepare
```

Every command below is written in its `docker compose exec -T web …` form.

**Branch:** `feat-29_cash-collection-hook` off the 1b branch. Scope: `feat_29`.

---

## A lesson from 1b, applied to this plan

In 1b the tasks that shipped **complete code** carried three defects into the
builder's hands — a parser that failed its own spec, a partial reading an ivar it
had no business reading, and a select that submitted while hidden. The one task
that gave **intent, constraints and the known traps** and let the builder read
the surrounding code produced better decisions than the plan would have.

So this plan states what must be true and what will bite, and gives literal code
only where the exact shape is load-bearing. Builders are expected to read the
neighbouring services and match them.

---

## Global constraints

Copy these into every task brief — subagents do not see this section.

### The constant-resolution trap

Anything under `Web::Cash::` must write `::Cash::Foo` with leading colons: inside
that namespace a bare `Cash` resolves to `Web::Cash` and raises a `NameError`
that reads like a missing file. This does not apply to `app/services/payments/`
or `app/services/sales/`, which are not nested under a `Cash` module — there,
plain `Cash::RecordSaleFromPayment` is correct.

### Payment methods are not channel names

`Payment::PAYMENT_METHODS` are `cash`, `bank_qr`, `bank_card`, `bank_transfer`,
`mercado_pago`. Cash channels are `cash`, `card`, `qr`, `transfer`,
`mercado_pago`, `usd`, `compensation`. Three of the five have different names,
and two channels have no payment method at all because they are manual-only.

There is exactly one mapping table and it lives on `CashMovement`. It fetches
without a default, so an unmapped method raises rather than silently producing a
movement with no arca — which is the failure mode `account_for_channel` was
hardened against in 1a.

### One `Payment` = one `CashMovement`

The collection services already group tenders by method and create one `Payment`
per method, so a sale split between cash and card yields two payments and
therefore two movements, one per arca — which is how the spreadsheet records it.
Do not batch, do not merge, do not create a movement per tender.

### Explicit calls, never a callback

The three collection services call the cash service **explicitly, inside their
existing transaction**. Do not add an `after_create` on `Payment`. The project
already made this choice for stock — `StockMovement` has no callbacks and the
services write it after the fact — and this module will not introduce the
opposite convention.

If the cash call fails, the whole collection fails. Follow the nested-service
pattern already in the codebase (`Purchasing::CreatePurchase` raises
`ValidationError, result.errors.join(", ")` on a failed inner `Result`), which
aborts the transaction immediately. Do not swallow the failure: a collection
that records money without recording where it went is worse than a collection
that fails.

### Automatic rows are read-only in the cash module

A movement with a `source_payment_id` is never edited and never deleted from the
day view. Editing it would make the two modules say different things about the
same money. Undoing happens through a reversing movement, never through an edit —
R-8's discipline, applied one layer up.

### Everything else

- Services return `Result`; controllers stay thin. HAML only.
- Code, comments and identifiers in ENGLISH; user-facing strings in Spanish.
- Comments minimal.
- `business_date` is always explicit, never an implicit `Date.current` buried in
  a service body.

---

## Task 1: The payment-method → channel map

**Files:** `app/models/cash_movement.rb`, `spec/models/cash_movement_spec.rb`

Add `PAYMENT_METHOD_CHANNELS` next to `CHANNEL_ACCOUNTS`, mapping each of
`Payment::PAYMENT_METHODS` to its cash channel, and a class method
`.channel_for_payment_method(method)` that fetches **without a default**.

Specs must assert:
- Each of the five methods maps to the channel the design names.
- An unmapped method raises `KeyError` rather than returning nil.
- **The map's keys are exactly `Payment::PAYMENT_METHODS`.** This is the example
  that matters: it fails the day someone adds a sixth payment method and forgets
  the cash module exists.
- Every value is a key of `CHANNEL_ACCOUNTS`, so no mapping can point at a
  channel that has no arca.

Do not reference `Payment::PAYMENT_METHOD_LABELS` for the labels — `CashMovement`
already has `CHANNEL_LABELS`.

---

## Task 2: `Cash::RecordSaleFromPayment`

**Files:** `app/services/cash/record_sale_from_payment.rb`,
`spec/services/cash/record_sale_from_payment_spec.rb`

One `Payment` in, one `CashMovement` out. Read
`app/services/cash/record_movement.rb` first and match its shape: `.call(**params)`,
a `Result`, a private `ValidationError`, the same rescue chain.

Signature: `payment:`, `user:`, and `description:` defaulting to nil.

What it writes:

| Field | From |
|---|---|
| `business_date` | `payment.payment_date` |
| `category` | `"sale"` |
| `channel` | `CashMovement.channel_for_payment_method(payment.payment_method)` |
| `account` | `CashMovement::CHANNEL_ACCOUNTS` for that channel |
| `amount` | `payment.amount`, positive |
| `source_payment` | the payment |
| `description` | the argument, or nil |
| `user` | the argument |

**It must refuse a payment that already has a movement.** Guard on
`CashMovement.exists?(source_payment_id: payment.id)` and return a failure
`Result`. Without it, a retried collection doubles the day's takings, and there
is no unique index that can express this — a reversal shares the same
`source_payment_id` on purpose.

Specs must cover: each of the five methods landing in the right arca, the
amount's sign, `source_payment_id` being set, the double-call guard, and a
payment whose method is not mapped surfacing as a failure `Result` rather than a
raised `KeyError`.

---

## Task 3: Hook `Payments::CollectSaleNote`

**Files:** `app/services/payments/collect_sale_note.rb`, its spec

Call `Cash::RecordSaleFromPayment` for each `Payment` the service creates, inside
the existing `ActiveRecord::Base.transaction`, after the payment and its
allocations exist. Description: **empty** — this is the ordinary counter sale and
a default text would be noise on every row.

The service currently has no `user:` parameter and the cash movement needs one.
Add it as a required keyword and update the caller
(`app/controllers/web/sale_notes/payments_controller.rb`) to pass `current_user`.
Update the existing specs for the new signature.

Specs must prove: a single-tender collection writes one movement in the right
arca; a **mixed-tender collection writes two movements, one per arca**, and their
amounts sum to the collection total; and a failure inside the cash service rolls
the whole collection back — no `Payment`, no `PaymentAllocation`, no
`CashMovement`, and the order still pending.

That rollback example is the one that matters. Write it first.

---

## Task 4: Hook `Payments::CollectOnAccount` and `Payments::AllocatePayment`

**Files:** both services, their specs

Same shape as Task 3. These two collect **older** sales, so money arrives today
against a sale made earlier. Both still write `sale` category movements — the
design is explicit that the distinction stays available through
`source_payment_id`, never through the description text.

Default descriptions, frozen at creation:

```
CollectOnAccount  →  "Cobro a cuenta — Nota 3345 — Juan Pérez"
AllocatePayment   →  "Cobranza cta. cte. — Juan Pérez"
```

Build them from the real record, not from a hardcoded string. If a payment is
allocated across several orders, decide what the note number reads as and say so
in your report — do not silently pick the first.

---

## Task 5: `Cash::ReversePayment`

**Files:** `app/services/cash/reverse_payment.rb`, its spec

Creates the reversing movement of an undone collection: same amount with the
opposite sign, same arca, same channel, the same `source_payment_id`, and a
description saying what it reverses. **The original row is never edited or
deleted.**

Two things the design is emphatic about:

- **It works the same whether the day is open or closed.** No branch on
  `daily_closing_id`, no branch on the date. A reversing movement is always
  legal; editing the original stops being legal the moment the day is sealed.
  One rule, nothing to remember.
- **The reversal is dated today**, not on the original's business date, because
  that is when it happened. Take `business_date:` as a keyword defaulting to
  `Date.current` so the date is explicit at the signature and specs can pin it.

It must refuse a payment that has no movement, and refuse to reverse twice.
Specs cover both, plus: the reversal lands on today even when the original is on
a sealed day, and the two rows sum to zero per arca.

---

## Task 6: `Sales::CancelOrder` reverses, and stops orphaning payments

**Files:** `app/services/sales/cancel_order.rb`, its spec, `WORKING_CONTEXT.md`

Two changes in one place, because they are the same bug seen from two sides.

**The reversal.** For each `Payment` reachable from the order's allocations, call
`Cash::ReversePayment` inside the existing transaction. Cancelling a collected
sale must give the money back in the ledger.

**The orphan.** `destroy_associated_allocations` destroys the
`payment_allocations` and leaves the `Payment` alive with nothing pointing at it.
This is a pre-existing bug, noted in `WORKING_CONTEXT.md`. It was survivable
while nothing read those payments; with the cash module it becomes material,
because the movement makes the money visible in the balances.

Decide deliberately what happens to a `Payment` whose only allocation is being
destroyed, and **write the reasoning into your report**: destroy it, mark it, or
leave it and explain why leaving it is now safe. Note that a payment may be
allocated across several orders and only one of them is being cancelled — that
case must not lose the other orders' money.

Order matters: reverse the cash **before** destroying the allocations, or the
service can no longer find which payments to reverse.

This service has `xit`-skipped stock specs already; leave those alone.

Update the `WORKING_CONTEXT.md` note to say what is now true.

---

## Task 7: Automatic rows are read-only in the day view

**Files:** `app/views/web/cash/movements/_row.html.haml`,
`app/views/web/cash/days/_drawer_zone.html.haml`,
`app/controllers/web/cash/movements_controller.rb`,
`app/policies/cash_movement_policy.rb`, specs

A row with a `source_payment_id` shows **no edit and no delete**, and the
controller refuses both even if the request is forged. Put the rule in
`CashMovementPolicy#update?` alongside the sealed check — the UI and the server
must agree, and the policy is where they meet.

The row also gets a discreet origin marker, so the cashier can see at a glance
what she does **not** have to load. Follow `docs/UI_DESIGN_SPEC.md`: this is
information, not decoration.

`_row` currently takes an `editable` local computed from the day. It now depends
on the movement too. Decide whether `editable` stays a local, becomes a policy
call in the view, or moves to a helper — and say which and why. Do not compute it
in two places.

Specs: a request spec proving `PATCH` and `DELETE` on an automatic row are
refused with a redirect and a flash, not a 500; and view-level examples paired
the way 1b's closed-day examples are — assert the affordances are absent on an
automatic row **and** present on a manual one in the same file.

---

## Task 8: The paper-number column

**Files:** `app/models/cash_movement.rb`, `app/services/cash/day_query.rb`,
`_drawer_zone.html.haml`, `_row.html.haml`, specs

The design's day-view columns include a paper number. It is not a column on
`cash_movements`: it comes from the payment's allocations' orders. A manual row
has none.

Add a `CashMovement` method that returns the paper numbers of the orders the
source payment was allocated to — plural, because a credit-account collection can
settle several notes at once. The view renders them; the view does not walk the
association.

**`Cash::DayQuery#drawer_movements` must eager-load it.** A day with twenty
collected sales would otherwise fire sixty queries. Add the `includes` and write
a spec that pins the query count — `ActiveRecord::Base.connection` instrumentation
or the `n_plus_one_control` idiom if the project has one; if it has neither, at
minimum assert the association is loaded so a future refactor cannot quietly drop
the `includes`.

---

## Task 9: `invoice_type` and `invoice_number` on `orders`

**Files:** migration, `app/models/order.rb`, `spec/factories/orders.rb`, specs

| Column | Type | Holds |
|---|---|---|
| `invoice_type` | `string`, **nullable** | `a` · `b` · `none` |
| `invoice_number` | `string` | present when the type is `a` or `b` |

**Four states, not three.** `none` means "it was decided this carries no
invoice". `NULL` means "nobody has said yet". If `none` were the default, every
sale would be born declaring it carries no invoice and there would be no way to
tell which ones nobody looked at. Same criterion as the closing's verification
columns: empty is not zero. Do not add a database default.

String-backed enum with `suffix: true`, following `orders.status`. A validation
that `invoice_number` is present when the type is `a` or `b`, and blank when it
is `none`.

Do NOT add the "warn at close about orders with no invoice type" rule — that
belongs with the closing flow, and the user has already ruled that it warns and
never blocks.

---

## Task 10: The cashier assigns the invoice when collecting

**Files:** `app/views/web/sale_notes/payments/new.html.haml`,
`app/controllers/web/sale_notes/payments_controller.rb`,
`app/services/payments/collect_sale_note.rb`, specs

The vendor writes the note without knowing whether it will be A, B or none; the
cashier assigns it at the moment she collects and issues the invoice.

Add the two fields to the collection form and pass them through the service, set
on the order inside the same transaction as the payment. Three options —
`Factura A`, `Factura B`, `Sin factura` — with the number field shown only for
the first two. There is already a Stimulus controller on that form
(`sale_note_payment_controller.js`); extend it rather than adding a second one.

Rarely does a split payment need an invoice, but when there is one **there is
exactly one per sale**, which is why these live on `orders` and not on the
movements.

---

## Verification for the whole slice

```
docker compose exec -T web bundle exec rspec
docker compose exec -T web bundle exec rubocop
```

Then, by hand:

1. Collect a sale note in cash. Open the day view: the row is there, it was not
   typed, and it carries the paper number and the origin marker.
2. Collect one split between cash and card. Two rows, two arcas, and "Ventas por
   canal" shows both.
3. Try to edit or delete either. Neither is offered.
4. Cancel that sale. A reversing row appears dated today and the channel panel
   returns to where it was.
5. Collect on account and check the description reads as the design says.
6. Assign Factura B and a number when collecting; reopen the order and it stuck.

---

## What 1c deliberately leaves out

- **The daily close.** 1d — including the warning about orders with no invoice
  type, and the exception that keeps the invoice fields editable on a sealed day.
- **The arca zone, movements between arcas, partner movements.** Tramo 2.
- **Compensation.** Tramo 4, with whatever the invoices module needs.
- **Reports.** Tramo 3.
