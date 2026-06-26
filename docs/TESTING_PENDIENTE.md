# TESTING_PENDIENTE.md

Backlog de cobertura de tests, derivado de la auditoría del **2026-06-26** contra la doctrina de `docs/TESTING_GUIDE.md` (capas + árbol + flujos de plata) y `WORKING_CONTEXT.md`.

Es un documento **de trabajo / transitorio**: cada ítem se borra a medida que se cubre. La doctrina estable vive en `AGENTS.md` → "Testing Rules" y en `TESTING_GUIDE.md`; esto es solo la lista de huecos pendientes.

## Hallazgo transversal — dos parsers de moneda

- `orders` y `payments` parsean montos con **`.to_f` crudo** (ej. `app/controllers/web/orders_controller.rb:122`). `.to_f` no valida, adivina: `"1.500.000,50".to_f == 1.5`, `"abc".to_f == 0.0`.
- `invoices` y `credit_notes` ya usan un **`CurrencyParser`** (`parse_amount`).
- Consecuencia para los specs hostiles: probablemente **pasen del lado invoices/credit_notes y fallen del lado orders/payments** — ahí está el bug real. El fix de fondo es unificar todos en un parser estricto (trabajo aparte de esta lista).

---

## 🔴 P1 — Input hostil en endpoints write-money

Todos tienen request spec, pero ninguno ataca el borde de parseo con valores hostiles: `"1.500.000,50"` (miles), negativo, `"abc"` (no numérico), vacío. Cada caso debe asertar **rechazo / normalización**, nunca aceptar un número equivocado.

- [ ] **`Sales::CreateOrder`** — POST `/web/orders`, `purchase_items[][unit_price]` hostil. (`spec/requests/web/orders_spec.rb`)
- [ ] **`Payments::AllocatePayment`** — POST `/web/customers/:id/payments`, `amount` + per-item `discounts` hostiles. (`spec/requests/web/customers/payments_spec.rb`)
- [ ] **`Payments::CollectSaleNote`** — completar: hoy solo cubre coma-decimal `"200,00"`; faltan miles `"1.500.000,50"`, negativo, `"abc"`, vacío en `tenders[][amount]`. (`spec/requests/web/sale_notes/payments_spec.rb`)
- [ ] **`Payments::CollectOnAccount`** — `amount_to_settle` / `discount_percent` hostiles **+** regla cash-only a nivel controller (hoy solo testeada en el service spec). (`spec/requests/web/payments_on_account/payments_spec.rb`)
- [ ] **`Invoices::CreateSimpleInvoice`** — POST `/web/invoices`, `amount` hostil vía `parse_amount`. (`spec/requests/invoices_spec.rb`)
- [ ] **Credit notes create** — completar: AR-format ya cubierto; faltan negativo/`"abc"`/vacío + `exchange_rate` hostil. (`spec/controllers/web/credit_notes_controller_spec.rb`)

## 🔴 P2 — Cobertura MISSING (no hay nada hoy)

- [ ] **`Inventory::AdjustStock`** — sin service spec **ni** request spec. Crear `spec/services/inventory/adjust_stock_spec.rb` (movimiento creado + efecto de `recalculate_current_stock!` + fallos) y request spec de `Web::Products::StockMovementsController#create` (signo purchase/sale/adjustment, `quantity=0` / tipo inválido → 422).
- [ ] **Invoice cancel** (`Web::InvoicesController#cancel`) — sin cobertura. Request spec: pending → `cancelled` + redirect/notice; no-pending → rechazado, status intacto.
- [ ] **Credit notes `update` / `destroy`** — sin request spec; el path `parse_amount` de update está sin probar. PATCH con `amount`/`exchange_rate` hostil + DELETE happy path.
- [ ] **`Sales::CancelOrder` restock** — aserciones en `skip`/`xit` ("stock movements temporarily disabled"); el restock no se verifica. Re-habilitar/reescribir cuando el restock esté activo. (`spec/services/sales/cancel_order_spec.rb`)

## 🟡 P3 — Correctitud de cálculo en read-money (reportes)

El filtro `product_source` está bien en los tres; **los montos no se asertan**. Sembrar tickets multi-renglón y asertar valores numéricos.

- [ ] **`SummaryQuery`** — asertar `:revenue`, `:reported` (dedup `DISTINCT ON ticket_number`), `:unique_products`. (`spec/services/sales_ledger/reports/summary_query_spec.rb`)
- [ ] **`SalesByDateQuery`** — asertar montos por fila; la lógica `SUM(CASE WHEN rn=1 ...)` con `ROW_NUMBER` está sin probar. (`spec/services/sales_ledger/reports/sales_by_date_query_spec.rb`)
- [ ] **`TopProductsQuery`** — asertar `total_revenue` / `total_quantity` (la frecuencia ya está bien). (`spec/services/sales_ledger/reports/top_products_query_spec.rb`)
- [ ] **`ImportCsv`** — agregar negativo y formato AR (menor: parser point-decimal propio). (`spec/services/sales_ledger/import_csv_spec.rb`)

## 🟢 P4 — Controllers sin request spec (más allá de lo de plata)

- [ ] `Web::SalesLedger::ImportsController` (ingesta de plata — amerita hostil) y `Web::SalesLedger::ReportsController` (render de agregados)
- [ ] `Web::SuppliersController` (CRUD completo con `destroy`)
- [ ] `Web::ProductsController` y `Web::DashboardController`

---

## ✅ Bien cubierto (no tocar — referencia)

- Saldos: `Customer#current_balance`, `Order#outstanding_balance` / `refresh_status_from_balance!` — OK con datos sembrados.
- `Inventory::MarkDelivered` — OK (unit + request + system).
- `CreditNote#available?` / `#exhausted?` / `#remaining_balance` — OK.
- `Invoices::MarkAsPaid` y `Invoices::ProcessPayment` — OK (reciben IDs/booleanos, no montos crudos → hostil N/A).
