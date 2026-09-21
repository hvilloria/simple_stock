# Balance general as a snapshot, the month on the dashboard — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the balance report into the two questions it was mixing: *how much money is there, and where* — a snapshot on Balance general — and *how is the month going* — a block on the dashboard.

**Architecture:** Two small read-only query objects replace one large one. Balance general loses its date range and its nine flow columns and shows four holdings at a single date. The dashboard gains an admin-only "Caja del mes" block with what was sold and what went on fixed expenses. No model, service, policy rule or database change.

**Tech Stack:** Rails 7.2, HAML, Tailwind, RSpec.

**Spec:** option B of the mockup the owner chose (https://claude.ai/artifact/UUwsKQSfv2WyneHpiNXV63). Background: `docs/CASH_MODULE_DESIGN.md` §3.1 (reporting groups), §8.3 (the current balance report), R-13.

**Branch:** `feat-33_cash-compensation`, scope `feat_33` — the owner treats these screens as gaps in the same module.

---

## Why this is changing

The owner found the balance report unfriendly, and named why. It answers two questions that live in different time frames:

- **"How much money is there, and where?"** is a photo: it is read at one moment. It is the number compared against the physical pile when money is counted (R-13).
- **"How is the month going?"** is a film: it is read over a period.

Mixing them forces a date range and nine columns — opening balance, sales, suppliers, fixed expenses, partner, between arcas, discrepancies, closing — to answer a question whose answer is the last one. The owner said partner, between arcas, discrepancies and the opening balance do not belong on it, and that its 📈 icon promised metrics the first question is not about.

## Decisions

**D1. Balance general is a snapshot at one date.** Four holdings — Efectivo, Banco, Mercado Pago, Dólares — each `SUM(amount)` over every movement of that reporting group up to and including the date. One date field, defaulting to today and capped at today: R-18 means nothing is dated in the future, so a later date cannot show anything new. A future date in the URL is treated as today. No range, no flow columns, no fixed-expense table.

**D2. No total, and dollars in dollars.** The four figures are not added up, and Dólares is shown as `US$`, never mixed into a peso sum. This is the rule the report already follows.

**D3. The movements that lost their columns are still in the numbers.** Partner movements, movements between arcas and count discrepancies all change a holding; they are simply not broken out. The history shows the rows behind any figure. Say so in one line under the cards.

**D4. Balance general's icon becomes ⚖️.** 📈 is freed; the history keeps 📒.

**D5. The month lives on the dashboard, for the admin only.** A block titled "Caja de <mes>" — "Caja de septiembre" — with two halves:

- **Vendido.** Everything sold in the month, invoiced or not — the owner's own definition: what was sold before any expense comes off. The peso total, then one line per reporting group (Efectivo, Banco, Mercado Pago), then **Compensación** on its own line when there is any, because it is a sale that reached no arca. A dollar sale is shown apart, as `US$`, and is not added to the peso total. A reversed collection is a sale movement with a negative amount, so it already reduces what was sold; that is correct and needs no special case.
- **Gastos fijos.** The peso total, then only the subcategories that had spending, largest first. A fixed expense paid in dollars — the Excel shows the August rent paid as `USD 2.300` — is shown apart, as `US$`, never added to the peso total.

The month is chosen with previous / next links; the next link does not go past the current month. Only an admin sees the block, because the whole cash module is admin-only for now; ask the policy rather than checking the role.

**D6. The word is "Vendido", not "Facturado".** Some sales carry no invoice, and the owner defined the figure as everything sold.

**D7. The old report's machinery goes.** `Cash::Reports::BalanceQuery` and `Cash::Reports::FixedExpenseBreakdownQuery` answer questions no screen asks any more; they and their specs are removed once nothing references them. The movement history keeps its date range — it still reads a period.

---

## Global Constraints

- **No host Ruby.** Everything runs in Docker; the stack is up. Commands are `docker compose exec -T web …`, in the FOREGROUND. Never launch a background job and idle. Full suite ONCE per task, at the end.
- **The cash module is admin-only.** Specs driving these screens sign in an admin.
- **`::Cash::Foo` with leading colons** anywhere under `Web::Cash::` — including any cash query called from `Web::DashboardController`.
- **Reports are query objects**, not services: no `Result`. A balance is always a `SUM`; there is no stored total anywhere.
- **Dollars never enter a peso sum** (D2, D5).
- **Count the queries.** Pin each new query object's cost with the `capture_sql` idiom already used in `spec/services/cash/day_query_spec.rb`, and make sure the fixtures contain the rows the query must handle — a USD movement and a compensation sale — or the count proves nothing. That trap has been hit twice in this module.
- **HAML drops an attribute whose value is `false`**; **`travel_to Date.new(...) { }` binds the block to `Date.new`** — use `do…end`.
- **The Tailwind watcher can go stale.** If a class you added does not appear in the browser, check `app/assets/builds/tailwind.css` before touching the markup.
- No change to models, services' rules, policies' rules or the database.
- UI copy in Spanish; code, comments and identifiers in English; comments minimal; HAML only; no queries or logic in views.
- **Do not `git commit` and do not stage.**

---

### Task 1: Balance general as a snapshot

**Files:**
- Create: `app/services/cash/reports/holdings_query.rb`, `spec/services/cash/reports/holdings_query_spec.rb`
- Modify: `app/controllers/web/cash/reports_controller.rb` (`balance`), `app/views/web/cash/reports/balance.html.haml`, `app/views/layouts/web/_sidebar.html.haml` (the icon), `spec/requests/web/cash/reports_spec.rb`

**Interfaces:**
- Produces: `Cash::Reports::HoldingsQuery.new(on: Date)` with `#holdings` → an Array of rows, one per reporting group in `REPORTING_GROUPS` order, each with `group`, `label` and `amount`.

What must be true:
- A holding is `SUM(amount)` for the group's arcas where `business_date <= on`. A movement dated after `on` is excluded; one dated exactly `on` is included.
- One SQL query for all four groups, pinned by a spec whose fixtures include a USD movement and a compensation sale — the compensation has no arca and belongs to no group.
- The balance action takes a single `on` parameter, defaulting to today; a future or unparseable date becomes today. It no longer calls `load_range`, and the history's use of it is untouched.
- The view shows four figures, Dólares as `US$`, no total, and the one-line note from D3. Nothing else: no range picker, no table, no fixed-expense breakdown.
- The sidebar icon for Balance general is ⚖️.

Specs: the query's inclusion boundary, the four groups in order, the exclusion of compensation, the query count; the request renders the four figures at a given date and at today by default, clamps a future date, renders no flow column headers ("Saldo inicial", "Socio", "Entre arcas", "Diferencias") — paired with an assertion that the four group labels are present — and still refuses a cashier.

- [ ] **Step 1:** Write the query and request specs; watch them fail.
- [ ] **Step 2:** Implement the query, the action and the view; change the icon.
- [ ] **Step 3:** Green; full suite once; rubocop. `BalanceQuery` and `FixedExpenseBreakdownQuery` are now unused by any screen — leave them for Task 3.

---

### Task 2: The month on the dashboard

**Files:**
- Create: `app/services/cash/reports/month_query.rb`, `spec/services/cash/reports/month_query_spec.rb`, `app/views/web/dashboard/_cash_month.html.haml`
- Modify: `app/controllers/web/dashboard_controller.rb`, `app/views/web/dashboard/index.html.haml`, `spec/requests/web/dashboard_spec.rb` (create it if the project has none — check first)

**Interfaces:**
- Produces: `Cash::Reports::MonthQuery.new(month: Date)` — any date inside the month — exposing `#sold_total` (pesos), `#sold_by_group` (Efectivo, Banco, Mercado Pago; pesos), `#sold_compensation` (pesos), `#sold_usd`, `#fixed_total` (pesos), `#fixed_by_subcategory` (only non-zero subcategories, largest first; pesos) and `#fixed_usd`. Figures are positive: this block reads as "what was sold" and "what was spent", not as signed movements.

What must be true (D5, D6):
- "Vendido" is every `sale` movement of the month, invoiced or not. Its peso total includes Efectivo, Banco, Mercado Pago and Compensación, and excludes USD, which is reported apart.
- "Gastos fijos" is every `fixed_expense` movement of the month. Its peso total excludes the ones paid in USD, which are reported apart.
- A reversed collection reduces what was sold, because its sale movement is negative. Spec it.
- The whole block costs a bounded number of queries, pinned with `capture_sql`; fixtures include a USD sale, a USD fixed expense, a compensation sale and a reversal.
- The dashboard renders the block only when the policy allows the cash module — ask the policy, do not check the role — and loads the query only in that case. Nothing about the rest of the dashboard changes.
- The block is titled "Caja de <nombre del mes>" in Spanish, with a previous-month link and a next-month link that does not appear for the current month. The month travels as a query parameter; an unparseable value falls back to the current month.
- A `US$` line appears only when there is a dollar figure; the Compensación line only when there is a compensation sale.

Specs: every rule above at the query level; at the request level, an admin sees the block with the right totals and a cashier does not — paired in the same file — and the month links navigate.

- [ ] **Step 1:** Write the query and request specs; watch them fail.
- [ ] **Step 2:** Implement the query, the partial and the controller change.
- [ ] **Step 3:** Green; full suite once; rubocop.

---

### Task 3: Remove the old report and update the design doc

**Files:**
- Delete: `app/services/cash/reports/balance_query.rb`, `app/services/cash/reports/fixed_expense_breakdown_query.rb` and their specs — only after grep shows nothing references them.
- Modify: `docs/TESTING_GUIDE.md` (its read-money catalogue lists both removed queries; list the two new ones instead), `docs/CASH_MODULE_DESIGN.md` — rewrite §8.3 for the snapshot and describe the dashboard block; update R-13, which says the owner filters a date range and compares the closing balance, to say he picks a date and compares the holdings; record in §2 that the nine-column report was built and replaced, and why.

What must be true:
- `grep` finds no reference to either removed class.
- The design doc no longer describes the nine-column report as current.

- [ ] **Step 1:** Grep, delete, grep again.
- [ ] **Step 2:** Update both docs.
- [ ] **Step 3:** Full suite once, green; rubocop.

---

## Verification

```
docker compose exec -T web bundle exec rspec
docker compose exec -T web bundle exec rubocop
```

By hand, as admin:

1. Balance general opens on today with four figures and ⚖️ in the sidebar. Pick an earlier date: the figures change, and nothing after that date counts.
2. Load a fixed expense paid in dollars. It does not change the peso total of "Gastos fijos" on the dashboard; it shows as a separate `US$` line.
3. Go to the previous month on the dashboard and back. There is no "next" link on the current month.
4. Sign in as a cashier: no cash block on the dashboard, no Balance general in the sidebar.
