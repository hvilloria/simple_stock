# WORKING_CONTEXT.md

## Purpose

Operational context of the current system.
Only includes behavior that is important for implementing features safely.

---

## App shell

* Rails **web** UI lives under the **`Web`** namespace (URLs prefixed with `/web/…` per `config/routes.rb`).
* **Devise**: sign-in only; **registrations are skipped** (`devise_for :users, skip: [:registrations]`).
* **Pundit** is included in `ApplicationController`; unauthorized access redirects with a flash.
* **`User#role`**: `vendedor`, `caja`, `admin` (string-backed enum). Policies in `app/policies/` gate actions.

---

## Web surface (what exists in routes)

* **Dashboard** (`web/dashboard#index`): metrics include “sales today” = sum of **active** (no canceladas) orders where **`created_at`** is today (not `sale_date`); receivables = sum of `Customer#current_balance` for customers with credit; low-stock lists; recent orders ordered by `created_at`.
* **Products**: CRUD without destroy; collection **`search`**; nested **`stock_movements`** new/create → `Inventory::AdjustStock` (stock location = **`StockLocation.first!`**).
* **Orders**: index/show/new/create; member **POST `cancel`** → `Sales::CancelOrder`. Create builds items from **`purchase_items`** params and resolves customer via **`Customer.mostrador`** when `customer_id` is blank or `"mostrador"`. El form `new` muestra solo Cliente · Tipo · N° Talonario · Productos (sin "Descuento" ni "Detalle de Pago"). Submit habilita con items + customer + paper_number.
* **Customers**: index/show/new/create/edit/update; **`debtors`** collection → lista de clientes con balance > 0 ordenada por deuda; nested **`payments`** new/create → `Payments::AllocatePayment` (module `Web::Customers`). El form de cobro permite distribuir el pago entre una o varias órdenes pendientes con método de pago independiente por fila.
* **Sale notes** (caja): index + cancel + nested payment new/create. `Web::SaleNotesController#index` lista `Order.immediate.pending`; `Web::SaleNotes::PaymentsController` cobra vía `Payments::CollectSaleNote` (descuento global 0/5/10, multi-tender, regla cash-only). Sidebar entry "Notas de pedido" visible para caja+admin con badge de pendientes.
* **Suppliers**: full `resources` (includes destroy).
* **Invoices**: simple-mode UI only (see below): index/new/create/show/edit/update; **`pending`** list; **`mark_supplier_paid`**; member **`mark_as_paid`**, **`cancel`** (pending invoice → `cancelled` via controller `update`, no service).
* **Credit notes**: full CRUD + **`supplier_invoices`** JSON for pending simple invoices by supplier — **direct ActiveRecord** in the controller (no dedicated service class).
* **Sales ledger**: **`imports`** index/create/show → `SalesLedger::ImportCsv`; **`reports#index`** → `SalesLedger::Reports::{SummaryQuery,SalesByDateQuery,TopProductsQuery}`. All three queries accept an optional **`product_source`** filter (`local` / `importado`), validated in the controller against `Entry::PRODUCT_SOURCES` before use. `TopProductsQuery` ranks by **frequency** (`COUNT(DISTINCT ticket_number)`) not quantity, returns top 15, and exposes `product_source` via `MIN(product_source)` in the SELECT.

---

## Core flows

### Orders

* `order_type` enum: `immediate` and `credit`. `status` enum: `pending`, `confirmed`, `cancelled` (default `pending`). Orders nacen `pending`; promueven a `confirmed` automáticamente cuando `outstanding_balance == 0` vía `Order#refresh_status_from_balance!` (llamado desde `Payments::AllocatePayment` y `Payments::CollectSaleNote` al final de la transacción).
* Created via `Sales::CreateOrder` (from `Web::OrdersController#create`). Solo recibe `customer:, items:, order_type:, paper_number:, channel:, source:, sale_date:`. **No captura pagos ni descuento** — el vendedor genera una nota; caja la cobra después (immediate) o entra a cuentas por cobrar (credit).
* `paper_number` es **obligatorio para toda nota** (live y from_paper).
* El form `new` muestra solo Cliente · Tipo · N° Talonario · Productos (sin "Descuento" ni "Detalle de Pago"). Submit habilita con items + customer + paper_number.
* Cancelled via `Sales::CancelOrder` (member cancel). `OrderPolicy#cancel_pending?` permite vendedor/caja/admin sobre notas `pending`; `#cancel?` solo admin sobre `confirmed`. El controller elige la policy method según el estado.
* **Stock no se modifica al vender hoy** — `Sales::CreateOrder` no crea `StockMovement`. La validación de disponibilidad corre **solo en `source: 'live'`**; el form `web/orders/new` envía **`source: from_paper` por defecto**, así que en la práctica **no se valida stock al vender** (se pueden agregar productos sin stock y cantidades libres; ver Key constraints). `Sales::CancelOrder` sí restockea vía `Inventory::AdjustStock` (asimétrico — comportamiento pre-existente, no parte de este feature).
* Descuento de inmediatas: caja lo aplica al cobrar vía `Payments::CollectSaleNote`. Cap `0 / 5 / 10` (global), distribuido a todos los `order_items`. **Regla:** solo permitido si la totalidad se paga en efectivo (validado en backend y enforced en Stimulus).
* Descuento de credit: sin cambios respecto a feat_09 (per-item 0-20% en primer cobro vía `Payments::AllocatePayment`; congelado tras la primera allocation).

### Stock

* Persisted movements are always **`StockMovement`** rows (product + **required** `stock_location`).
* **`Product#current_stock`** is refreshed by **`#recalculate_current_stock!`** (sum of movement quantities); **there are no `StockMovement` model callbacks** that update the product — callers/services do it after writes (e.g. `Inventory::AdjustStock`).
* UI and sales code paths use **`StockLocation.first!`** when a location is needed.

### Invoices (simple mode in the UI)

* **`Invoices::CreateSimpleInvoice`** creates **`has_items: false`**, **`status: pending`** records — **no stock movements**.
* **Supplier-side “payment”** in the UI is **`Invoice` status / `paid_at` / credits**, not the customer **`Payment`** model:
  * **`Invoices::MarkAsPaid`** — single simple invoice.
  * **`Invoices::ProcessPayment`** — batch for one supplier; can create **`AppliedCredit`** rows from **`CreditNote`** then mark invoices paid.
* **Canceling** a pending simple invoice (`Web::InvoicesController#cancel`) sets **`status: cancelled`** only — **still no stock** (consistent with simple invoices not touching inventory).

### Customer account payments (`Payment` + `PaymentAllocation` models)

* **`Payment`** representa un *tender* (entrega física de dinero con un método único). Pertenece al `customer`; **ya no tiene `order_id`**. Validaciones: `amount > 0`, `payment_method ∈ %w[cash transfer check card]`, `payment_date presente`. **Ya no exige `has_credit_account?`** — los Payments pueden pertenecer a clientes retail (mostrador).
* **`PaymentAllocation`** (join `payment_allocations(payment_id, order_id, amount)`) distribuye el monto de un Payment sobre una o varias órdenes. Validaciones: `amount > 0`, `order_belongs_to_payment_customer`, `amount_within_order_outstanding_balance` (con `where.not(id: id)` para excluir la allocation actual). Índice único `(payment_id, order_id)`.
* **Invariante:** `payment.amount == SUM(payment.allocations.amount)` — garantizada por el servicio, no por una validación de modelo.
* **`Payments::AllocatePayment`** servicio del cobro de credit. Recibe `customer:, payment_date:, notes:, allocations: [{order_id:, amount:, payment_method:, item_discounts: {oi_id => percent}}]`. Acepta órdenes `pending` o `confirmed` (rechaza solo `cancelled`). Agrupa por `payment_method`, crea un `Payment` por grupo + sus `PaymentAllocation`s, y llama `refresh_status_from_balance!` en cada orden tocada al final de la transacción.
* **`Sales::CancelOrder`** destruye las `PaymentAllocation` de la orden cancelada (`@order.payment_allocations.destroy_all`); los `Payment` **quedan vivos** (known limitation — pueden quedar huérfanos sin asignación, el `current_balance` del cliente los sigue descontando como crédito a favor).
* `Order#outstanding_balance` = `total_amount − payment_allocations.sum(:amount)` para órdenes no canceladas (cualquier tipo). Promoción automática a `confirmed` cuando llega a 0 vía `Order#refresh_status_from_balance!`, invocado desde `Payments::AllocatePayment` y `Payments::CollectSaleNote` al final de la transacción.
* `Customer#current_balance` = `SUM(credit_orders.total_amount) − SUM(payment_allocations on credit orders)` filtrando `status IN ('pending', 'confirmed')`. `Customer.with_outstanding_balance` usa la misma fórmula.
* **`Customer#last_payment_date`** / **`#days_without_paying`** — helpers para la vista de deudores.
* **`Customer.with_outstanding_balance`** scope — clientes cuyas ventas a crédito confirmadas superan el total de sus pagos.
* **`Web::Customers::PaymentsController#new`** muestra una tabla con todas las órdenes pendientes; cada fila tiene checkbox de inclusión, monto editable, y método de pago propio. El submit POST recibe `params[:allocations]` indexado (`allocations[N][order_id|include|amount|payment_method]`) y delega en `Payments::AllocatePayment`. Stimulus controller (`payment_allocation_controller.js`) recalcula resumen en vivo y deshabilita submit si no hay órdenes tildadas.
* **`payments` table** ya no tiene la columna `order_id` — la relación vive en `payment_allocations`.

### Sales ledger

* **`SalesLedger::ImportCsv`** writes import batches + ledger entries; it **does not** create **`Order`**, **`StockMovement`**, or **`Payment`** (see comments in the service).

---

## Key constraints

* Do **not** bump **`products.current_stock`** ad hoc in controllers/views — keep stock changes through **`StockMovement`** + **`#recalculate_current_stock!`** as the code already does in services.
* **Validate stock before selling (`live` source only)** — enforced in **`Sales::CreateOrder`** against **`current_stock`**; the UI flow defaults to `from_paper`, which skips this (see Order validation below).
* **Un `Payment` representa un tender** con método único; su distribución sobre órdenes vive en `payment_allocations`. **`Customer#current_balance`** = sum(credit orders confirmadas `total_amount`) − sum(`payment_allocations` sobre esas credit orders). Los Payments asignados a ventas `immediate` no afectan el balance.
* **`Customer` validation:** `retail` customers cannot have `has_credit_account: true` (`retail_cannot_have_credit_account`).
* **`Order` validation:** `paper_number` is **required for every order** (unconditional `presence: true`, not unique). `Sales::CreateOrder` validates stock availability for `source: 'live'` only; it skips the check for `from_paper`. **`web/orders/new` submits `source: from_paper` by default** (hidden field), so the UI sales flow does **not** validate stock at sale time — the vendor is trusted to know the product exists (no inventory system yet). The `live` branch and its stock validation remain in the service for future use.
* Not every HTTP action uses a service: e.g. **pending invoice cancel** and **credit note** CRUD use **`update` / `save` / `destroy`** on models directly.
* **Fechas/horas timezone-aware** — usar siempre **`Date.current` / `Time.current`**, nunca `Date.today` / `Time.now`. La app corre en **UTC** (no hay `config.time_zone`); `Date.today` toma la zona del SO y produce off-by-one cerca de medianoche (causó tests flaky en `Invoice`/`Customer`). Todo el código y los specs usan `Date.current`.

---

## Active services (called from app code paths)

* **Sales:** `Sales::CreateOrder`, `Sales::CancelOrder`
* **Inventory:** `Inventory::AdjustStock`
* **Invoices:** `Invoices::CreateSimpleInvoice`, `Invoices::MarkAsPaid`, `Invoices::ProcessPayment`
* **Payments:** `Payments::AllocatePayment`, `Payments::CollectSaleNote`
* **Sales ledger:** `SalesLedger::ImportCsv`; report query objects under **`SalesLedger::Reports::`** (from `Web::SalesLedger::ReportsController`)

**Present in codebase but not wired to `Web::` controllers:** `Purchasing::CreatePurchase`, `Purchasing::CancelPurchase`, **`Inventory::SyncFromCsv`** (invoked from **`lib/tasks/inventory.rake`**, not from HTTP).

---

## Important gaps

* **`Payment` / `PaymentAllocation`** web UI under `web/customers/:customer_id/payments` (new/create only) usa `Payments::AllocatePayment`; permite distribuir un cobro entre varias órdenes con método de pago independiente por fila.
* **No web UI** for itemized purchasing: **`Purchasing::CreatePurchase`** is used in **seeds/specs**, not `Web::InvoicesController`.
* **`Inventory::SyncFromCsv`** is **rake-only**, not exposed in routes.

---

## Notes

* For behavior, **read the service (or controller action) in question** — “thin controller” is the norm for orders and ledger imports, but invoices/credit notes mix services and direct updates.
