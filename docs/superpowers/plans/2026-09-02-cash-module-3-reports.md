# Cash module — tramo 3: the balance report and the movement history

Builds on tramos 1 and 2. **This tramo kills the `Caja Grande` sheet.**

Two screens, both **admin only**, both pure reports with no actions. Design spec:
`docs/CASH_MODULE_DESIGN.md` §3.1, §8.3, §8.4, and rules R-13, R-17.

---

## Environment

Docker only, stack up, every command `docker compose exec -T web …` in the
FOREGROUND.

**Branch:** `feat-32_cash-reports` off the tramo 2 branch. Scope: `feat_32`.

---

## Global constraints

Copy into every task brief.

- **`::Cash::Foo` with leading colons** anywhere under `Web::Cash::`.
- **Reports are query objects, not services** — `docs/CODE_PATTERNS.md` has the
  shape. They return relations or plain hashes, never a `Result`.
- **A balance is always `SUM(amount)`.** There is no cached total anywhere and
  there must not be one.
- **One copy of the amount rules** — `Cash::AmountParser`. These screens read, so
  they should not need it at all; if you think you do, you are doing something
  wrong.
- Partials take locals. HAML only. Code in English, UI strings in Spanish.
- Comments minimal.
- **HAML landmine:** it DROPS an attribute whose value is `false`, so a Stimulus
  boolean value must be rendered as `x.to_s`.

---

## The reporting groups

The report is coarser than the arcas. Four groups (§3.1):

```
Efectivo      = drawer + main_cash + change_fund
Banco         = bank
Mercado Pago  = mercado_pago
USD           = usd
```

This is the grouping that was deliberately NOT built in slice 1a — an
`ARS_ACCOUNTS` constant was removed there precisely because its only obvious use
was a grand peso total the report must not show. **There is no grand total. USD
stands alone, in dollars.**

---

## Task 1: `CashMovement::REPORTING_GROUPS`

**Files:** `app/models/cash_movement.rb`, `spec/models/cash_movement_spec.rb`

The four groups above, plus whatever lookup the report needs (group → accounts,
and account → group).

Specs, in the style the module already uses for `CHANNEL_ACCOUNTS`:
- **Every arca belongs to exactly one group**, and every group's accounts are
  real arcas. That is the example that fails the day a seventh arca is added and
  the report silently stops counting it.
- The Efectivo group is the three cash arcas, and nothing else.

---

## Task 2: `Cash::Reports::BalanceQuery`

**Files:** `app/services/cash/reports/balance_query.rb`, its spec

Takes a date range. Returns one row per reporting group with these figures:

```
opening balance · sales · suppliers · fixed expenses · partner ·
between arcas · discrepancies · closing balance
```

**Columns are named after the categories, never "income/expense".** A deposit is
money changing place, not an expense — that naming is the whole reason the
spreadsheet was confusing.

**THE INVARIANT, and the reason this task exists:**

```
opening + sales + suppliers + fixed + partner + transfers + discrepancies == closing
```

for **every** group, in every scenario. A row that does not reconcile is a bug,
not something to audit by hand. Write that as its own describe block over a
seeded month with movements of every category in every group, including
transfers whose two legs land in DIFFERENT groups — that is the case most likely
to break it.

**THE DETAIL THAT WILL BREAK RECONCILIATION IF YOU MISS IT:**
`opening_balance` is a category, and those rows exist on exactly one date at
startup. A range that contains that date has rows belonging to no column, and the
row will not reconcile.

Resolve it as: **the opening balance figure is everything before the range PLUS
any `opening_balance`-category rows inside it.** That matches R-17 — an opening
balance is the starting position, not money that came in — and keeps the
arithmetic closed. Write a spec for a range that contains the startup date.

Definitions to implement literally:
- opening = `SUM(amount)` for the group where `business_date < from`, plus
  `opening_balance` rows in range
- closing = `SUM(amount)` for the group where `business_date <= to`
- each category column = `SUM(amount)` for the group, that category, in range

Nothing here is a stored total.

---

## Task 3: The balance report screen

**Files:** `app/controllers/web/cash/reports_controller.rb` (or similar),
`app/views/web/cash/reports/`, `config/routes.rb`,
`app/policies/` (admin only), sidebar, specs

Date range with presets: **week · fortnight · month · custom**. The owner chooses
his own cadence — the system imposes none and offers no counting workflow. Reuse
`filter_form_controller` and the filter idiom from `orders#index`; do not invent
a second one.

One row per group, the eight columns above. **Admin only** — the cashier does not
see this screen at all, and the policy must be real, not just a hidden nav item.

No grand total row. No "Contar" button, no counting workflow, no diagnostics
about unclosed days — the owner cut all of those explicitly. Build the table and
the range picker and stop.

Sidebar entry, admin-gated, following the existing idiom.

---

## Task 4: The fixed-expense breakdown

**Files:** the query, the view, specs

Fixed expenses expands to a breakdown **by subcategory and arca** — the six
subcategories (alquiler, sueldos, cargas sociales, impuestos, servicios, gastos
de local) against the arcas they were paid from.

This is the part of the spreadsheet the owner actually reads, so it has to be
easy to scan. It expands within the report; it is not a second screen.

The breakdown's total must equal the fixed-expenses column it expands. Spec that.

---

## Task 5: `Cash::Reports::MovementsQuery` and the history screen

**Files:** the query, controller, views, routes, specs

The drill-down: when a number looks odd, this is where the rows behind it are.

Filters: **arca · category · period · description search**. Same mechanics as
`orders#index` and `invoices#index` — `filter_form_controller` plus pagy.

**The arca filter offers the four reporting GROUPS; the column shows the fine
arca.** Filter coarse, read fine, and the totals still agree with the report. Do
not offer six arcas in the filter and four in the report — they would disagree
and nobody would know which to trust.

**Read-only, always.** Editing happens on the open day and nowhere else. No edit
affordances, no delete, not even for an admin. **Admin only.**

---

## Task 6: Transfer rows name their counterpart

**Files:** `app/models/cash_movement.rb`, the history view, specs

A row of category `internal_transfer` states its counterpart: **"hacia Banco"**,
**"desde Caja del día"**.

Why it matters: filtered to one arca you only see one leg, and a large row with
no counterpart reads as money that evaporated. This is the single most confusing
thing the report can show, and one phrase fixes it.

The counterpart is the other row sharing the `transfer_group_id`. Put the lookup
on the model and **eager-load it in the query** — a page of fifty history rows
must not fire fifty extra queries. Pin that with a spec the way slice 1c pinned
the paper-number column: count the SQL and expect none while rendering.

---

## Verification for the whole tramo

```
docker compose exec -T web bundle exec rspec
docker compose exec -T web bundle exec rubocop
```

By hand, on a month with real movements:

1. Open the balance report as admin. Every row reconciles: opening plus the
   columns equals closing.
2. As a cashier, the report is unreachable and absent from the sidebar.
3. Expand fixed expenses. The breakdown totals the column it expands.
4. Filter the history by Efectivo. Transfers show their counterpart, so no row
   looks like money that vanished.
5. Change the range to a fortnight. Everything still reconciles.

---

## What tramo 3 deliberately leaves out

- **Compensation.** Tramo 4, with whatever the invoices module needs.
- **P&L, monthly result, closing series, per-partner balances, any metric.** All
  cut by the owner. Do not add a chart, a trend, or a percentage anywhere.
- **A counting workflow.** Verification is the owner reading this report against
  the physical pile, at whatever cadence he chooses.
