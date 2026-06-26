# TESTING_GUIDE.md

Reference for the testing doctrine defined in `AGENTS.md` → "Testing Rules". This file holds the money-flow catalog and worked examples. The rule and decision tree live in `AGENTS.md`; this is consultation material.

## What counts as a "money flow"

A flow that creates, persists, or computes amounts, discounts, balances, or prices. Two kinds, tested differently.

### Write-money (amount params come in → require a hostile-input case)

- `Sales::CreateOrder` — per-item `unit_price` + write-back to `product.price_unit`
- `Payments::AllocatePayment` — per-order amounts + `item_discounts`
- `Payments::CollectSaleNote` — 0/5/10 cash-only discount, multi-tender
- `Payments::CollectOnAccount` — `amount_to_settle`, discount, lowers `total_amount`
- `Invoices::CreateSimpleInvoice` / `MarkAsPaid` / `ProcessPayment` — amounts + `AppliedCredit`
- Credit notes CRUD — `amount`, `exchange_rate`

### Read-money (no input to attack, but calculation correctness is critical → unit/request with seeded data)

- `Customer#current_balance` / `Order#outstanding_balance` — balance formulas
- `SalesLedger::Reports::{SummaryQuery, SalesByDateQuery, TopProductsQuery}` — report aggregates
- `SalesLedger::ImportCsv` — imports amounts (does not create Order/Payment/StockMovement)

Out of scope on purpose: `Inventory::AdjustStock` / `Inventory::MarkDelivered` — quantity/delivery, not money; stock has its own critical rule (see `CLAUDE.md`).

> This catalog is derived from WORKING_CONTEXT's active-services list — verify each entry against code when it changes. The Builder adds a new entry here whenever a feature introduces a new money flow (see `AGENTS.md` → "Testing Rules" → Responsibilities). It is a helper for completeness, not the gate that decides a test layer — the decision tree does that.

## Worked example — hostile input on a money flow

The backend must not trust the client to send a clean number. Ruby's `.to_f` does not validate, it guesses — and guesses wrong with the app's own AR format:

```ruby
"1.500.000,50".to_f   # => 1.5    (stops at the first dot)
"abc".to_f            # => 0.0     (no error)
"200000.50".to_f      # => 200000.5
```

A request spec for any write-money flow should POST hostile values directly (bypassing the Stimulus normalization) and assert the backend rejects or normalizes them — never silently accepts a wrong number:

- AR-formatted string `"1.500.000,50"` → must not become `1.5`
- non-numeric `"abc"` → rejected, not `0`
- negative / blank → rejected

A system spec is the wrong place for this: Stimulus would prevent sending the bad value, so the backend's defense would never run.
