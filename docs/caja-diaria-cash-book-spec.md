# Caja Diaria (Daily Cash Book) — Design Spec

> Status: **design agreed, ready for planning**. This document is the design context
> to hand to a planning skill (`rails-planner` / `writing-plans`). It is a spec, not an
> implementation plan — it fixes the domain model, the decisions, and the scope of v1.

---

## 1. Purpose

Replicate, inside the app, the manual Excel cash book the business keeps today
(`Caja - Julio 2026.xlsx`): a **multi-account daily ledger with carry-forward funds**.

The business tracks all daily money movements — inflows (mostly sales, plus scrap,
adjustments) and outflows (fixed expenses, supplier payments) — across a few **funds**,
and carries the accumulated balance forward day by day. This is today the *only* record
of the money side of the business; it lives outside the app entirely.

The core goal is to **track the three main funds — Efectivo (cash), Banco (bank),
Mercado Pago** — plus USD as a secondary balance tracker, and to **link inflows to the
sales (`Order`s) already created in the app** via `paper_number`.

---

## 2. What the Excel actually is (domain analysis)

The workbook has one sheet per day (`010726` = 1 Jul 2026), plus aggregate sheets.

**Daily sheet — each row is one money movement:**

| Excel column      | Meaning                                             |
|-------------------|-----------------------------------------------------|
| `Descripción`     | Free text; **blank when it's a plain linked sale**  |
| `Nro talonario`   | = the app's `paper_number` (links to an `Order`)    |
| `Nro Factura`     | Invoice number (free text)                          |
| `Entrada`         | Inflow amount (mutually exclusive with Salida)      |
| `Salida`          | Outflow amount                                      |
| `Canal`           | Efectivo · Mercado Pago · Banco · Tarjeta · USD     |
| `Tipo de venta`   | e.g. "Uno" (secondary, not modeled in v1)           |
| `Tipo de factura` | A / B (kept as metadata; no tax logic in v1)        |

**Right-hand block per day** = running balance **per fund** (Efectivo, Mercado Pago,
Banco, USD), tracked in **Neto/Bruto**, plus **Remanente** (funds carried from prior
days) and a **Total**.

**Aggregate sheets:**

- `Ingresos` — date, importe, descripción, canal.
- `Egresos` — date, importe, descripción, canal, **`Fondo Impactado`** (`Gastos fijos` /
  `Proveedor`) — an expense category.
- `Caja Grande` — the dashboard: saldo por fondo, ventas brutas, gastos por proveedor vs.
  gastos fijos, totals.

**Key observations that shaped the model:**

1. **`Remanente` is not a stored snapshot** — it is simply the cumulative running balance
   carried across days. The day's opening balance is *derivable* from prior movements.
2. **A "channel" funds a "fund".** On 1 Jul there is a **Tarjeta** sale of 888.125 and the
   day's `Saldo Banco` is exactly 888.125 — yet the daily balance block only tracks
   Efectivo, Mercado Pago, Banco, USD (**no Tarjeta balance**). So *how the money arrived*
   (channel) and *where the balance accumulates* (fund) are two different axes.
3. **Sales are only one source of inflows** — there are also non-sale inflows ("Chatarra"
   = scrap, "Aumento de Remanente" = adjustment) and **outflows (expenses / supplier
   payments) which do not exist anywhere in the app today.**

---

## 3. Central decision — standalone ledger, its own source of truth

**Chosen: a standalone `CashMovement` ledger, manually entered, mirroring the Excel,
with an optional link to `Order` (Option C).**

Rejected alternative — auto-deriving the ledger from `Payment` records — because:

- Most sales run `source: from_paper` and **never pass through in-app payment capture**
  (`Payments::CollectSaleNote` et al.), so an auto-fed ledger would cover only a fraction
  of movements and be confusingly partial.
- The ledger is strictly **broader** than Payments: it must record **outflows** (which the
  app has no concept of) and **non-sale inflows**.
- Coupling to the payment pipeline (hooks in `CollectSaleNote`, `CollectOnAccount`,
  `AllocatePayment`, plus reversal in `CancelOrder`) is high-risk for little v1 value.

Because in-app payment capture is partial today, this is **not** double data entry — it is
the **first structured capture of the money side of the business**.

**Future seam (not v1):** the channel constants deliberately align with
`Payment::PAYMENT_METHODS`, so a later reconciliation view between Payments and
CashMovements is cheap to add. See §9.

---

## 4. Core idiom — balance = SUM(movements)

Model funds exactly like the project's stock rule:

> **A fund's balance = SUM of its `CashMovement`s. It is never stored or mutated
> directly — always recomputed from movements.**

This mirrors `Product#current_stock = sum(StockMovement)` and the "stock is never mutated
directly" rule. Consequences:

- `Remanente` (carry-forward) and a day's opening balance are **derived**, not stored.
- The initial seed balance (the Excel's starting `Remanente`) is represented as **one
  opening-balance `CashMovement` per fund**, dated at go-live — keeping the invariant clean.

---

## 5. Domain model

### 5.1 `CashMovement` (new model / table)

Proposed fields (final column shapes are the planner's call):

- `movement_date` (date, default `CURRENT_DATE`, timezone-aware via `Date.current`)
- `amount` (decimal 10,2, always **positive**)
- `direction` (string enum: `in` / `out`) — inflow vs. outflow
- `channel` (string enum, see §5.3)
- `fund` (string enum, see §5.2) — **derived from `channel`** but **persisted on the row**
  (user's explicit choice: store both). Balances are summed by `fund`.
- `category` (string enum, see §5.4)
- `description` (string, nullable — blank for plain linked sales)
- `paper_number` (string, nullable) — mirrors `Order#paper_number`
- `invoice_number` (string, nullable)
- `order_id` (bigint, nullable FK) — optional link to a sale (§6)
- `transfer_group_id` (uuid/bigint, nullable) — groups the two legs of a transfer (§7)
- `user_id` (bigint, FK) — who recorded it

**Note on v1 simplification (decision):** only **Bruto** (the actual cash amount that hits
the fund) is stored. **No Neto / IVA split** in v1. `tipo_factura` (A/B) may be stored as
plain metadata but drives no tax logic. Neto can be derived later for reporting if needed.

**Note on USD (decision):** USD is its own fund; its balance stays **in dollars**. **No FX
conversion** in v1 — it is a balance tracker only.

### 5.2 Funds (fixed constants — no user management)

`efectivo` · `banco` · `mercado_pago` · `usd`

These are the three main funds plus the USD tracker. Backed by a constant/enum in the
model, in the style of `Payment::PAYMENT_METHOD_LABELS` (single source of truth, Spanish
labels for the UI).

### 5.3 Channels and the channel → fund mapping

A **channel** describes how the money arrived; it **funds** a fund. The mapping is fixed:

| Channel (constant)         | UI label (es)        | → Fund          |
|----------------------------|----------------------|-----------------|
| `efectivo`                 | Efectivo             | `efectivo`      |
| `mercado_pago`             | Mercado Pago         | `mercado_pago`  |
| `bank_card` (Tarjeta)      | Tarjeta              | `banco`         |
| `bank_qr` (QR)             | QR                   | `banco`         |
| `bank_transfer` (Transf.)  | Transferencia        | `banco`         |
| `usd`                      | USD                  | `usd`           |

Both `channel` and the derived `fund` are **persisted** on each movement (per user's
decision): the channel keeps the "how paid" detail; the fund drives balances. The mapping
lives in one place (a constant hash / method) and is applied when a movement is created.

**Alignment note:** the channel constants intentionally match `Payment::PAYMENT_METHODS`
(`cash`/`efectivo`, `bank_qr`, `bank_card`, `bank_transfer`, `mercado_pago`) so a future
Payments↔Caja reconciliation needs no translation layer. The planner should confirm the
exact naming (`cash` vs `efectivo`) against the existing enum and pick one consistent set.

### 5.4 Categories (`Fondo Impactado` and inflow kinds)

A `category` enum tags the nature of the movement and powers the aggregate reports:

- Inflows: `venta` (linked/plain sale), `chatarra` (scrap), `ajuste` (adjustment /
  "Aumento de Remanente"), `otro_ingreso`.
- Outflows: `gastos_fijos`, `proveedor`, `otro_egreso`.
- Both legs of a transfer: `transfer` (§7).

Constant/enum with Spanish UI labels. `Ingresos` / `Egresos` views are just
`direction` + `category` filters; the "Caja Grande" dashboard groups outflows by
`gastos_fijos` vs `proveedor`.

---

## 6. Order linkage

- `CashMovement#order_id` is **nullable**. Many rows are non-sale, so linkage is optional.
- On the entry form, typing/selecting a `paper_number` looks up the `Order` and
  **prefills** description / amount / channel — but the amount stays **editable** (the cash
  that actually hits the fund can differ from the order total due to discount/rounding).
- **No auto-creation** of movements from orders, and **no auto-feed from Payments** in v1.

---

## 7. Transfers between funds

Transfers **will** happen (e.g. withdrawing cash from the bank, a Mercado Pago payout
settling into Banco). Modeled to preserve the `balance = SUM(movements)` invariant:

- A transfer is **two legs in one atomic operation**: an `out` movement on the source fund
  and an `in` movement on the destination fund, **same amount**, `category: transfer`,
  both sharing a `transfer_group_id`.
- Created by a dedicated service in a transaction (see §8). No special-casing in the
  balance sum — the two legs net correctly on their own.
- This also lets future reconciliation (e.g. pulling Mercado Pago's movements for a day)
  drop transfers in as ordinary paired legs.

---

## 8. Services (return `Result`, per project convention)

- **`Cash::RecordMovement`** — creates a single `in`/`out` movement. Resolves `fund` from
  `channel`, optionally links the `Order`. Validates amount > 0, valid channel/category.
- **`Cash::TransferFunds`** — creates the two-legged transfer atomically (source `out` +
  destination `in`, shared `transfer_group_id`). Validates distinct funds, amount > 0.
- **Balance** — a query object (e.g. `Cash::FundBalance` / `Cash::DailyLedgerQuery`) that
  sums movements per fund (optionally up to a date) and produces the per-day running
  balances and the dashboard figures. **No stored balances.** Follows the Query Object
  pattern in `docs/CODE_PATTERNS.md`.

Trivial single-row edits/deletes may use direct ActiveRecord in a thin controller (project
already allows this for trivial single-model actions); transfers must go through the
service so both legs stay consistent.

---

## 9. Surfaces (UI)

Namespaced under `Web` (`/web/...`), HAML only, following `docs/UI_DESIGN_SPEC.md`
(slate base; red reserved for the logo). Suggested routes/screens:

1. **Day view** (`/web/caja?date=…`, default today) — the daily sheet: the day's movements
   (in/out, channel, category, description, paper/invoice, order link) + **per-fund running
   balances** + day totals. Entry form to add a movement; separate action for a transfer.
2. **Dashboard ("Caja Grande")** — current balance of the three funds + USD, plus
   ventas / gastos-by-category for the selected period.
3. **Ingresos / Egresos** — aggregate lists, i.e. `direction` + `category` filters over a
   date range.

Sidebar entry "Caja" (label in Spanish), visible per §10.

---

## 10. Roles / authorization (Pundit)

- `caja` and `admin`: full write (record movements, transfers, edit/delete).
- `vendedor`: read-only (or no access — planner to confirm against existing policies).
- New `CashMovementPolicy` (+ transfer authorization) in `app/policies/`.

---

## 11. Editing & audit

- v1: movements are **editable/deletable** before any day-close, because the balance is a
  live re-sum (cheap to recompute). Simplicity over audit trail for v1.
- If an audit trail is wanted later, switch to append-only + reversal movements (the stock
  model's philosophy). Not v1.

---

## 12. Explicitly out of scope for v1

- **Cerrar caja / arqueo** (close-the-day with a physical cash count vs. expected balance,
  and locking the day). Deferred to a later version; the model doesn't preclude it.
- **Neto / Bruto (IVA) split and any tax logic.** Bruto only.
- **USD FX conversion.** Balance tracker in dollars only.
- **Auto-feeding the ledger from `Payment`s** and **auto-creating movements from `Order`s.**
- **Linking outflows to `Invoice`/`Purchase`.** Supplier outflows are recorded as a
  movement with `category: proveedor` + free-text invoice reference; `invoice_id` linkage
  is a future seam.
- **User-managed funds/accounts.** Funds and channels are fixed constants.
- **`Tipo de venta`** column ("Uno", …) — not modeled in v1.

---

## 13. Decisions locked (from the design session)

1. Funds are fixed constants; **no** user-managed accounts. ✔
2. USD = balance tracker in dollars, no conversion. ✔
3. v1 stores **Bruto only**; no Neto/IVA split. ✔
4. `category` enum drives Ingresos/Egresos/dashboard. ✔
5. Optional, editable `order_id` link via `paper_number`; no auto-creation. ✔
6. Supplier/expense outflows recorded as movements (`category: proveedor`), not coupled to
   Invoices in v1. ✔
7. **Arqueo / cerrar caja deferred** to a later version. ✔
8. **Transfers between funds are in scope**, modeled as two-legged atomic movements. ✔
9. Roles: `caja` + `admin` write, `vendedor` read-only. ✔
10. **Channel ≠ fund**; store **both**. Channel→fund mapping fixed
    (`Tarjeta`/`QR`/`Transferencia` → `Banco`). ✔

---

## 14. Existing code to follow (patterns & anchors)

- **Stock idiom** to mirror: `Inventory::AdjustStock` → `StockMovement` →
  `product.recalculate_current_stock!`; the "never mutate directly" rule (`CLAUDE.md`,
  `docs/DEVELOPMENT_GUIDE.md` §Stock).
- **Service + Result**: `app/services/result.rb`, `app/services/**` (e.g.
  `Sales::CreateOrder`, `Payments::CollectSaleNote`).
- **Query objects**: pattern in `docs/CODE_PATTERNS.md` §Query Object.
- **Payment methods** (for channel alignment / future reconciliation):
  `Payment::PAYMENT_METHOD_LABELS` in `app/models/payment.rb`
  (`cash bank_qr bank_card bank_transfer mercado_pago`).
- **Order fields** for linkage: `orders.paper_number`, `orders.sale_date`,
  `orders.channel`, `orders.total_amount` (see `db/schema.rb`).
- **Pundit policies**: `app/policies/`, `ApplicationController` unauthorized handling.
- **Web namespace + HAML + Tailwind**: `app/controllers/web/`, `docs/UI_DESIGN_SPEC.md`.
- **Timezone rule**: always `Date.current` / `Time.current` (app runs UTC).

---

## 15. Open items for the planner to resolve

- Exact channel constant naming (`cash` vs `efectivo`) to stay consistent with the existing
  `Payment` enum while reading naturally in the Caja UI.
- Whether `direction` is a separate column or encoded as a signed `amount` (spec assumes a
  positive `amount` + `direction` enum for readability; planner may prefer signed).
- Precise route/namespace naming (`/web/caja` vs `/web/cash_book`) and sidebar wording.
- Seed/opening-balance mechanism for the initial `Remanente` per fund at go-live.
