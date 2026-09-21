# Cash module — slice 1d: the daily close

Builds on 1a (data foundation), 1b (day view and drawer-zone loading) and 1c (the
collection hook).

**This is the slice where the daily spreadsheet dies.** After it, a day can be
counted, closed and sealed, and nothing can silently rewrite it afterwards.

Design spec: `docs/CASH_MODULE_DESIGN.md` §7.2, §7.3, §8.2, and rules R-4, R-6,
R-8, R-9, R-10, R-11, R-12.

---

## Environment

No host Ruby — everything runs in Docker, stack already up. Every command is
written `docker compose exec -T web …`, run in the FOREGROUND.

**Branch:** `feat-30_cash-daily-close` off the 1c branch. Scope: `feat_30`.

---

## Global constraints

Copy into every task brief.

- **`::Cash::Foo` with leading colons** anywhere under `Web::Cash::`. A bare
  `Cash` there resolves to `Web::Cash` and raises a NameError that reads like a
  missing file. Services under `app/services/cash/` use plain names.
- **Turbo Streams**, established in 1b: a response is a list of
  `turbo_stream.<verb> "<dom-id>"` calls, nothing more. Every target needs a
  stable id; a stream aimed at a missing id fails silently.
- **Partials take locals, never controller ivars.**
- Services return `Result`. HAML only. Code in English, user-facing strings in
  Spanish. Comments minimal.
- `business_date` is always explicit.

### `Cash::RecordMovement` cannot write a transfer leg

It refuses `category: "internal_transfer"` on purpose — a one-legged transfer
would break the arca it never reached, and that guard was added deliberately in
1a. `Cash::RecordTransfer` therefore writes its two rows itself, inside one
transaction. That is the exception, and the only one.

### Sealing must not use `update_all`

`update_all` skips callbacks, so it would walk straight past the immutability
guard and would happily re-seal rows already sealed by another closing. Seal by
iterating and calling `update!` on each row, scoped to `daily_closing_id: nil`.
The guard reads the **persisted** `daily_closing_id`, which is precisely why
stamping an unsealed row is allowed and stamping a sealed one is not.

---

## Task 1: `Cash::RecordTransfer`

**Files:** `app/services/cash/record_transfer.rb`, its spec

One operation, **two rows**, one transaction, sharing a `transfer_group_id`
(uuid). Same amount with opposite signs, category `internal_transfer`, no channel
and no subcategory.

Signature: `from:`, `to:`, `amount:`, `business_date:`, `user:`, `description:`.

Rules it enforces:
- `from` and `to` must both be valid arcas and must differ.
- The amount is positive on input; the service assigns the signs. A caller
  passing a negative amount is an error, not an instruction to swap direction.
- Amount parsing follows `Cash::RecordMovement`: a Numeric or a strict plain
  decimal string, nothing else. Reuse its parsing rather than writing a second
  one — extract it if that is cleaner, but do not duplicate the rules.
- Both rows are written or neither is. A spec must prove that a failure on the
  second leg leaves zero rows, not one.

Specs: the two rows exist with opposite signs and one shared
`transfer_group_id`; each arca's balance moves by the right amount; same-arca and
unknown-arca are refused; the atomicity case above; and hostile amounts
(`"1.500"`, `"abc"`, `0`) are refused writing nothing.

---

## Task 2: `Cash::CloseDay`

**Files:** `app/services/cash/close_day.rb`, its spec

The heart of the slice. Signature: `business_date:`, `counted_cash:`, `user:`,
plus optional `payway_batch_total:`, `mercado_pago_total:` and `note:`.

**In this order, inside one transaction:**

1. **Refuse if the day is already closed.** There is no reopening, ever (R-10).
2. **Record the discrepancy**, if `counted_cash != expected`, where `expected` is
   `CashMovement.drawer_balance_on(date)`. One `cash_discrepancy` movement on
   `drawer` for `counted_cash - expected`. Never adjust an existing row (R-11).
3. **Emit the transfer.** If `counted_cash > 0`, `Cash::RecordTransfer` from
   `drawer` to `main_cash` for `counted_cash`. If it is zero there is nothing to
   wrap and no transfer is written.
4. **Seal every movement of the date** — including the two rows just written —
   by stamping `daily_closing_id`. Iterate with `update!`; see the constraint
   above about `update_all`.
5. **Persist the `DailyClosing`** with `expected_cash`, `counted_cash`, the two
   optional verification totals, `closed_at` and the user.

**The invariant that must be tested directly:** after the close,
`CashMovement.drawer_balance_on(date)` is **exactly zero**, in every case — count
matches, count short, count over, expected negative, counted zero. Write that as
its own describe block with a table of cases. If it is not zero the close is
wrong, whatever else passes.

Other specs: a second close of the same date is refused and writes nothing; the
discrepancy movement is absent when the count matches; every movement of the date
carries the closing id afterwards, including the transfer legs and the
discrepancy; a movement of a **different** date is untouched; and the whole thing
rolls back if any step fails.

The note is optional on purpose. Requiring a justification for a shortfall nobody
can explain pushes the operator to change the counted number until it balances,
which destroys the data the rule exists to preserve. Do not add a presence
validation on it.

---

## Task 3: `DailyClosingPolicy`, route and controller

**Files:** `app/policies/daily_closing_policy.rb`,
`app/controllers/web/cash/closings_controller.rb`, `config/routes.rb`, specs

`caja` and `admin` can close a day; nobody else. There is no update and no
destroy — `DailyClosing` has
`has_many :cash_movements, dependent: :restrict_with_exception` and R-10 says
there is no reopening. Say that in the policy rather than leaving `update?`
inheriting `false` by accident.

Route inside the existing `namespace :cash`. The controller has `new` (renders
the modal) and `create` (calls `Cash::CloseDay`). A successful close redirects
back to the day; a failure re-renders the modal with the reason.

Request specs: a cashier closes; a seller cannot; closing twice is refused; a
failure does not leave a partial close.

---

## Task 4: The closing modal

**Files:** `app/views/web/cash/closings/new.html.haml` and its partials, a
Stimulus controller if one is needed, `app/views/web/cash/days/show.html.haml`
(the button), specs

A modal over the day view — **not** a separate screen — with four blocks, in the
order of §7.2. Three typeable fields in the whole thing, only one required.

**1. Completeness.** How many movements the day has, a warning about the day's
uncollected sale notes (the same query behind the sidebar badge, scoped by date),
and a warning about the day's sales with **no invoice type assigned** —
`invoice_type` NULL, which 1c made possible to ask.

Both **inform and never block**. The paper pad is also used for quotes, and
blocking on a missing invoice type would only make somebody type an arbitrary
value in order to close. The close seals `cash_movements`, not `orders`, so the
invoice can be filled in the next day without reopening anything.

**2. Drawer count.** Show the expected amount and one field for what she counted.
**There is no "it matches" button** — a button gets pressed without counting.

**When the expected amount is negative, do not show a negative number.** The
screen reads, in the operator's words:

```
El cajón no alcanzó: los fajos pusieron $300.000.
A envolver: $0.
```

**3. Digital verification.** Two optional fields: the Payway terminal batch total
and the day's Mercado Pago total. Next to each, what the app has recorded, and
the difference if any. Informs, never blocks. QR and transfers also land in
`bank` and are not verified in V1 — do not add a third field.

**4. Close.** The amount to wrap and the button.

Size: it is a large modal, and it scrolls. Do not fight to fit everything above
the fold.

---

## Task 5: Transfer legs as paired rows

**Files:** `app/services/cash/day_query.rb`,
`app/views/web/cash/movements/_row.html.haml`, `_drawer_zone.html.haml`, specs

A transfer's two legs are two rows sharing a `transfer_group_id`. In the day
table they appear as two visually paired rows, with a link marker — so each row
stays one arca and one direction and the table remains one-to-one with the model.
**Do not group them before rendering.**

Note the drawer zone only ever shows the `drawer` leg (the other is `main_cash`,
which belongs to the arca zone, tramo 2). Decide what the pairing marker means
when only one leg is on screen, and say so.

Transfer legs are never editable: they are written as a pair and a single leg
cannot be corrected alone. Add that to `CashMovementPolicy#update?` alongside the
sealed and automatic checks, with a spec.

---

## Task 6: System spec for the close

**Files:** `spec/system/web/cash_daily_close_spec.rb`

The parts a request spec cannot see: the modal opens over the day, the expected
amount is shown, typing a different count and closing produces the discrepancy
row and the transfer, and afterwards the day is read-only — no live row, no edit
affordances, the marker visible.

Follow `spec/system/web/cash_live_row_spec.rb`. Run it three times before
reporting; a flaky browser spec is worse than none.

---

## Verification for the whole slice

```
docker compose exec -T web bundle exec rspec
docker compose exec -T web bundle exec rubocop
```

By hand, on a day with sales and an expense loaded:

1. Open the close. The expected amount matches what the panel says to wrap.
2. Type exactly that and close. No discrepancy row; two transfer rows; the day
   turns read-only.
3. On a fresh day, type less than expected. A discrepancy row appears for the
   difference and the close still proceeds.
4. Try to close the same day again. Refused.
5. Load a day whose expenses exceed its sales and close it. The screen says the
   bundles covered it and shows zero to wrap, never a negative number.

---

## What 1d deliberately leaves out

- **The arca zone and the transfer form.** Tramo 2. `Cash::RecordTransfer` exists
  after this slice but only the close calls it.
- **Partner movements.** Tramo 2.
- **The balance report and the movement history.** Tramo 3.
- **Compensation.** Tramo 4.
- **Editing the invoice type on a sealed day.** The design allows it as the one
  deliberate exception; the screen for it belongs with the sales module, not here.
