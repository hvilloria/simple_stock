# Cash module — tramo 2: the arca zone

Builds on tramo 1 (1a data foundation, 1b day view, 1c collection hook, 1d daily
close). After tramo 1 the daily spreadsheet is dead. **This tramo kills the
`Egresos` and `Ingresos` sheets.**

Design spec: `docs/CASH_MODULE_DESIGN.md` §7.1, §7.3, §8.1, §9, and rules R-1,
R-2, R-6, R-7, R-16.

---

## Environment

No host Ruby — everything runs in Docker, stack already up. Every command is
`docker compose exec -T web …`, run in the FOREGROUND.

**Branch:** `feat-31_cash-arca-zone` off the 1d branch. Scope: `feat_31`.

---

## What the arca zone is, and what it is not

The drawer zone and the arca zone are separated by **the count**, not by
frequency or amount. Whatever passes through the drawer is counted at night;
everything else is not.

- **Drawer zone** (built in 1b): sales and counter expenses. Nobody picks an
  arca — sales route by channel, expenses come out of the till.
- **Arca zone** (this tramo): everything that does not pass through the drawer.
  Paying a supplier from the bank, a utility bill from Mercado Pago, a deposit, a
  partner withdrawal. **Here the arca is declared**, because there is no default.

This is a daily zone, not an exceptional one. The spreadsheet shows 414 outflows
across seven months — about 59 a month, two or three per business day, and nine
on 03/08 alone. **So loading here has to be as fast as the drawer zone: a live
row, plus an arca column.** Do not build a modal-per-row.

The query is already decided and must not become a column:

```
drawer zone = category = 'sale' OR account = 'drawer'   (built in 1b)
arca zone   = everything else
```

R-6 still rules: an expense paid out of the till goes in the drawer zone against
`drawer`; the same expense paid out of a bundle because the till was empty goes
here against `main_cash`. The cashier knows which, because she is the one who
took the bill. **The count is defined by `account`, never by the zone.**

---

## Global constraints

Copy into every task brief.

- **`::Cash::Foo` with leading colons** anywhere under `Web::Cash::`.
- **Turbo Streams**, as established in 1b: a list of `turbo_stream.<verb> "<id>"`
  calls, nothing more. Every target needs a stable id; a stream aimed at a
  missing id fails silently.
- **Partials take locals, never controller ivars.**
- **One copy of the amount rules.** `Cash::AmountParser` is the only strict
  reading of a money amount. Do not add a second.
- **Model predicates, not restated conditions.** `#sealed?`, `#automatic?` and
  `#transfer?` are read by both the policy and the views. The row asks
  `policy(movement).update?` rather than restating its conditions. Keep it that
  way.
- Services return `Result`. HAML only. Code in English, user-facing strings in
  Spanish. Comments minimal.

---

## Task 1: `Cash::DayQuery#arca_movements`

**Files:** `app/services/cash/day_query.rb`, its spec

The complement of `drawer_movements`, over the same date, ordered the same way,
with the same eager loading.

Specs must be written as the **mirror** of the existing drawer-zone examples: the
supplier paid from the bank belongs here and not there; the bags bought out of a
bundle belong here; a USD sale does NOT (it is a sale, so it is a drawer-zone
row even though its arca is `usd`); an expense paid from the till does not.

**Add one example asserting the two zones partition the day**: every movement of
the date appears in exactly one of them, and together they are all of them. That
is the property that stops a row going missing when either query is edited later.

---

## Task 2: The arca zone table and its live row

**Files:** `app/views/web/cash/days/_arca_zone.html.haml`,
`app/views/web/cash/movements/_arca_row.html.haml` and `_arca_live_row.html.haml`,
`_day.html.haml`, `app/controllers/web/cash/movements_controller.rb`, its stream
views, `app/policies/cash_movement_policy.rb`, specs

Below the drawer zone, on the same day screen, with the same live-row gesture:
Enter saves, a fresh empty row appears, the focus returns to the first field.

**Columns:** description · **arca** · inflow · outflow · actions. No channel —
channels only exist on sales, and a sale is never an arca-zone row.

**Categories offered here**, from `CashMovementPolicy`:
- `suppliers`, `fixed_expense` (with its subcategory) — everyone
- `partner` — **admin only** (R-16). Not friction, permission: it simply is not
  in the cashier's selector, and the controller refuses it for her too.
- NOT `sale` (drawer zone), NOT `internal_transfer` (Task 3), NOT
  `opening_balance` (the rake task, once, at startup), NOT `cash_discrepancy`
  (emitted by the close).

**The sign** is derived from the category as in the drawer zone —
`suppliers` and `fixed_expense` are outflows. **`partner` is the exception: it
goes both ways.** Taking money out is an outflow, putting it back is an inflow,
same category (R-16). Decide how the cashier expresses the direction and say why;
whatever you choose, it must not be a typed minus sign.

Note R-16's second half, which is a rule about data and not about UI: when a
partner pays business costs with money he took, **each payment carries its real
category** — salaries are `fixed_expense/salaries`, not `partner`. Only what he
keeps is `partner`. Nothing in the code enforces this; do not try to.

The existing `Web::Cash::MovementsController#create` already does most of this
work for the drawer zone. Extend it rather than writing a second controller —
but the arca is now submitted rather than derived, so the two zones diverge on
exactly that point. Keep the divergence small and obvious.

---

## Task 3: The movement-between-arcas form

**Files:** `app/controllers/web/cash/transfers_controller.rb`,
`app/views/web/cash/transfers/`, `config/routes.rb`,
`app/javascript/controllers/`, specs

**Movements between arcas do not go through the live row.** They need two arcas
and the live row has one column; a second column would sit empty on the ~54
single-arca movements a month and "origin/destination" means nothing when paying
a utility bill. Around five transfers a month.

A **"+ Movimiento entre arcas"** button opens a short form below the table:
**Desde · Hacia · Monto · Descripción.** No category field — it is implied. No
sign — the direction determines it.

**The form previews the two rows it will write, before saving.** This is the only
gesture in the app where one action produces two records, so it must not be a
surprise. The preview shows both rows as they will appear in the table.

Calls `Cash::RecordTransfer`, which already exists from slice 1d and already
writes both legs in one transaction sharing a `transfer_group_id`. Do not
reimplement any of that.

Known recurring cases, worth having in mind when choosing defaults: Mercado Pago
→ Banco (to pay suppliers), Caja grande → Banco (deposits), Caja grande →
Remanente (topping up change).

Refuse a closed day, as the drawer zone does.

---

## Task 4: Partner movements are admin-only, enforced

**Files:** `app/policies/cash_movement_policy.rb`,
`app/controllers/web/cash/movements_controller.rb`, specs

The category list is per role. `partner` appears for admin and not for `caja`,
and the controller refuses it from a cashier even if the request is forged.

There is no partner identity field and no partner account — the owner cut both.
`partner` is a category and nothing else. Do not add a `partner_id`, a name
field, or a per-partner balance.

Specs: an admin loads a partner movement in both directions; a cashier cannot,
and is refused with a redirect and a flash rather than a 500; the selector does
not offer it to her.

---

## Task 5: System spec for the arca zone and the transfer form

**Files:** `spec/system/web/cash_arca_zone_spec.rb`

The parts a request spec cannot see: the arca live row saves and refocuses; the
subcategory select appears only for a fixed expense; the transfer form opens,
previews **two** rows before saving, and after saving the drawer-zone or
arca-zone table shows the leg that belongs to it with its "Entre arcas" marker.

Follow `spec/system/web/cash_live_row_spec.rb` and
`spec/system/web/cash_daily_close_spec.rb`. Run it three times before reporting.

---

## Verification for the whole tramo

```
docker compose exec -T web bundle exec rspec
docker compose exec -T web bundle exec rubocop
```

By hand:

1. Load a supplier payment from the bank in the arca zone. It appears there, not
   in the drawer zone, and the amount to wrap does not move.
2. Load the same expense against `drawer` instead. It appears in the drawer zone
   and the amount to wrap drops. That is R-6, visible.
3. Move money from Mercado Pago to Banco. The preview shows two rows; after
   saving, neither appears in the drawer zone, and both carry the marker.
4. As a cashier, confirm "Socio" is not in the selector. As admin, confirm it is
   and that it goes both ways.
5. Close the day. The arca-zone rows are sealed too and stop being editable.

---

## What tramo 2 deliberately leaves out

- **The balance report and the movement history.** Tramo 3 — including the
  expense breakdown by type, which the spreadsheet has and this screen does not.
- **Compensation.** Tramo 4.
- **A partner account or per-partner balance.** Cut by the owner; `partner` is
  only a category.
