# TESTING_PENDIENTE.md

Test coverage backlog, derived from the audit of **2026-06-26** against the doctrine in `docs/TESTING_GUIDE.md` (layers + tree + money flows) and `WORKING_CONTEXT.md`.

This is a **working / transitional** document: each item is deleted as it gets covered. The stable doctrine lives in `AGENTS.md` → "Testing Rules" and in `TESTING_GUIDE.md`; this is only the list of pending gaps.

## Cross-cutting finding — two currency parsers

- `orders` and `payments` parse amounts with **raw `.to_f`** (e.g. `app/controllers/web/orders_controller.rb:122`). `.to_f` does not validate, it guesses: `"1.500.000,50".to_f == 1.5`, `"abc".to_f == 0.0`.
- `invoices` and `credit_notes` already use a **`CurrencyParser`** (`parse_amount`).
- Consequence for hostile specs: they will probably **pass on the invoices/credit_notes side and fail on the orders/payments side** — that is where the real bug is. The deep fix is to unify all of them under a strict parser (work separate from this list).

---

## 🔴 P1 — Hostile input on write-money endpoints

They all have a request spec, but none attack the parsing edge with hostile values: `"1.500.000,50"` (thousands), negative, `"abc"` (non-numeric), empty. Each case must assert **rejection / normalization**, never accept a wrong number.

- [ ] **`Sales::CreateOrder`** — POST `/web/orders`, hostile `purchase_items[][unit_price]`. (`spec/requests/web/orders_spec.rb`)
- [ ] **`Payments::AllocatePayment`** — POST `/web/customers/:id/payments`, hostile `amount` + per-item `discounts`. (`spec/requests/web/customers/payments_spec.rb`)
- [ ] **`Payments::CollectSaleNote`** — complete: today it only covers the decimal-comma case `"200,00"`; missing thousands `"1.500.000,50"`, negative, `"abc"`, empty in `tenders[][amount]`. (`spec/requests/web/sale_notes/payments_spec.rb`)
- [ ] **`Payments::CollectOnAccount`** — hostile `amount_to_settle` / `discount_percent` **+** the cash-only rule at the controller level (today only tested in the service spec). (`spec/requests/web/payments_on_account/payments_spec.rb`)
- [ ] **`Invoices::CreateSimpleInvoice`** — POST `/web/invoices`, hostile `amount` via `parse_amount`. (`spec/requests/invoices_spec.rb`)
- [ ] **Credit notes create** — complete: AR-format already covered; missing negative/`"abc"`/empty + hostile `exchange_rate`. (`spec/controllers/web/credit_notes_controller_spec.rb`)

## 🔴 P2 — MISSING coverage (nothing today)

- [ ] **`Inventory::AdjustStock`** — no service spec **nor** request spec. Create `spec/services/inventory/adjust_stock_spec.rb` (movement created + effect of `recalculate_current_stock!` + failures) and a request spec for `Web::Products::StockMovementsController#create` (purchase/sale/adjustment sign, `quantity=0` / invalid type → 422).
- [ ] **Invoice cancel** (`Web::InvoicesController#cancel`) — no coverage. Request spec: pending → `cancelled` + redirect/notice; non-pending → rejected, status intact.
- [ ] **Credit notes `update` / `destroy`** — no request spec; the `parse_amount` path of update is untested. PATCH with hostile `amount`/`exchange_rate` + DELETE happy path.
- [ ] **`Sales::CancelOrder` restock** — assertions in `skip`/`xit` ("stock movements temporarily disabled"); the restock is not verified. Re-enable/rewrite when the restock is active. (`spec/services/sales/cancel_order_spec.rb`)

## 🟡 P3 — Calculation correctness on read-money (reports)

The `product_source` filter is fine in all three; **the amounts are not asserted**. Seed multi-line tickets and assert numeric values.

- [ ] **`SummaryQuery`** — assert `:revenue`, `:reported` (dedup `DISTINCT ON ticket_number`), `:unique_products`. (`spec/services/sales_ledger/reports/summary_query_spec.rb`)
- [ ] **`SalesByDateQuery`** — assert per-row amounts; the `SUM(CASE WHEN rn=1 ...)` logic with `ROW_NUMBER` is untested. (`spec/services/sales_ledger/reports/sales_by_date_query_spec.rb`)
- [ ] **`TopProductsQuery`** — assert `total_revenue` / `total_quantity` (frequency is already fine). (`spec/services/sales_ledger/reports/top_products_query_spec.rb`)
- [ ] **`ImportCsv`** — add negative and AR format (minor: it has its own point-decimal parser). (`spec/services/sales_ledger/import_csv_spec.rb`)

## 🟢 P4 — Controllers without a request spec (beyond the money ones)

- [ ] `Web::SalesLedger::ImportsController` (money ingestion — deserves hostile) and `Web::SalesLedger::ReportsController` (aggregate rendering)
- [ ] `Web::SuppliersController` (full CRUD with `destroy`)
- [ ] `Web::ProductsController` and `Web::DashboardController`

---

## ✅ Well covered (do not touch — reference)

- Balances: `Customer#current_balance`, `Order#outstanding_balance` / `refresh_status_from_balance!` — OK with seeded data.
- `Inventory::MarkDelivered` — OK (unit + request + system).
- `CreditNote#available?` / `#exhausted?` / `#remaining_balance` — OK.
- `Invoices::MarkAsPaid` and `Invoices::ProcessPayment` — OK (they receive IDs/booleans, not raw amounts → hostile N/A).
</content>
</invoke>
