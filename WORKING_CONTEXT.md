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

* **Dashboard** (`web/dashboard#index`): metrics include “sales today” = sum of **confirmed** orders where **`created_at`** is today (not `sale_date`); receivables = sum of `Customer#current_balance` for customers with credit; low-stock lists; recent orders ordered by `created_at`.
* **Products**: CRUD without destroy; collection **`search`**; nested **`stock_movements`** new/create → `Inventory::AdjustStock` (stock location = **`StockLocation.first!`**).
* **Orders**: index/show/new/create; member **POST `cancel`** → `Sales::CancelOrder`. Create builds items from **`purchase_items`** params and resolves customer via **`Customer.mostrador`** when `customer_id` is blank or `"mostrador"`. El form `new` ordena la columna izquierda como **Cliente → Productos → Descuento → Detalle de Pago**; el card "Descuento" se oculta cuando `order_type = credit` (descuento de credit vive en feat_09).
* **Customers**: index/show/new/create/edit/update; **`debtors`** collection → lista de clientes con balance > 0 ordenada por deuda; nested **`payments`** new/create → `Payments::AllocatePayment` (module `Web::Customers`). El form de cobro permite distribuir el pago entre una o varias órdenes pendientes con método de pago independiente por fila.
* **Suppliers**: full `resources` (includes destroy).
* **Invoices**: simple-mode UI only (see below): index/new/create/show/edit/update; **`pending`** list; **`mark_supplier_paid`**; member **`mark_as_paid`**, **`cancel`** (pending invoice → `cancelled` via controller `update`, no service).
* **Credit notes**: full CRUD + **`supplier_invoices`** JSON for pending simple invoices by supplier — **direct ActiveRecord** in the controller (no dedicated service class).
* **Sales ledger**: **`imports`** index/create/show → `SalesLedger::ImportCsv`; **`reports#index`** → `SalesLedger::Reports::{SummaryQuery,SalesByDateQuery,TopProductsQuery}`. All three queries accept an optional **`product_source`** filter (`local` / `importado`), validated in the controller against `Entry::PRODUCT_SOURCES` before use. `TopProductsQuery` ranks by **frequency** (`COUNT(DISTINCT ticket_number)`) not quantity, returns top 15, and exposes `product_source` via `MIN(product_source)` in the SELECT.

---

## Core flows

### Orders

* `order_type` enum values: **`immediate`** (was `cash`) and **`credit`**. `cash` is reserved for payment methods.
* Created via **`Sales::CreateOrder`** (from `Web::OrdersController#create`). Acepta **`payments:`** array de `{ amount:, payment_method: }` — **obligatorio para `immediate`** (suma debe igualar `total_amount` con tolerancia $0.01; el origen `from_paper` está exento), **opcional para `credit`** (suma ≤ `total_amount`). Cada entrada produce un `Payment` + `PaymentAllocation` apuntando a la nueva orden.
* El formulario de nueva venta muestra un bloque "Detalle de Pago" multi-fila (método + monto por fila, con add/remove) visible para ambos tipos de venta. Badge "Requerido" para immediate / "Opcional" para credit. El submit valida en vivo que la suma coincida con el total.
* Cancelled via **`Sales::CancelOrder`** (member cancel).
* Confirmed sales create **`StockMovement`** rows with **`movement_type: sale`** via **`Inventory::AdjustStock`** (signed quantity: **outbound is negative** in the implemented paths).
* **`Sales::CancelOrder`** restocks using **`Inventory::AdjustStock`** with **`movement_type: adjustment`** and a **positive** quantity per line (not a second `sale` movement).
* **Descuento:** `order_items.discount_percent` is editable for both immediate and credit orders, capped 0–20% (absolute cap enforced in `OrderItem`). Immediate orders receive a global `discount_percent` (0–10) at creation via `Sales::CreateOrder`, which distributes it to each item. Credit orders have their per-item percent set at the first `Payments::AllocatePayment` call (0–20 per item); once any `PaymentAllocation` exists for the order the discounts are frozen and cannot be changed. `orders.original_total_amount` (pre-discount, NOT NULL) and `order_items.discount_percent` (default 0, NOT NULL) are always persisted. `total_amount` holds the post-discount value — all downstream logic (payments, dashboard, `outstanding_balance`) reads `total_amount` unchanged. Helpers: `Order#discount_amount`, `Order#discount_percent_display`.

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
* **`Payments::AllocatePayment`** servicio principal del web. Recibe `customer:, payment_date:, notes:, allocations: [{order_id:, amount:, payment_method:}]`, **agrupa por `payment_method`** y crea un `Payment` por grupo + sus `PaymentAllocation`s en una sola transacción. Valida que cada orden pertenezca al cliente, sea `credit + confirmed`, y que el monto no exceda el `outstanding_balance` de cada orden.
* **`Sales::CreateOrder`** ahora crea Payments + Allocations para **ambos tipos** de orden vía el array `payments:`. Para órdenes `immediate` la suma debe igualar el total (excepto `from_paper`); para `credit` puede ser parcial o cero. Cada entrada genera un `Payment` + `PaymentAllocation`.
* **`Sales::CancelOrder`** destruye las `PaymentAllocation` de la orden cancelada (`@order.payment_allocations.destroy_all`); los `Payment` **quedan vivos** (known limitation — pueden quedar huérfanos sin asignación, el `current_balance` del cliente los sigue descontando como crédito a favor).
* **`Order#outstanding_balance`** = `total_amount - payment_allocations.sum(:amount)` para `credit + confirmed`; `0` para `immediate` o `cancelled`.
* **`Customer#current_balance`** = `SUM(credit_orders.total_amount) − SUM(payment_allocations on credit orders)`. **Los payments de ventas immediate no afectan el balance de crédito** (a diferencia del modelo anterior). `Customer.with_outstanding_balance` usa la misma fórmula.
* **`Customer#last_payment_date`** / **`#days_without_paying`** — helpers para la vista de deudores.
* **`Customer.with_outstanding_balance`** scope — clientes cuyas ventas a crédito confirmadas superan el total de sus pagos.
* **`Web::Customers::PaymentsController#new`** muestra una tabla con todas las órdenes pendientes; cada fila tiene checkbox de inclusión, monto editable, y método de pago propio. El submit POST recibe `params[:allocations]` indexado (`allocations[N][order_id|include|amount|payment_method]`) y delega en `Payments::AllocatePayment`. Stimulus controller (`payment_allocation_controller.js`) recalcula resumen en vivo y deshabilita submit si no hay órdenes tildadas.
* **`payments` table** ya no tiene la columna `order_id` — la relación vive en `payment_allocations`. `Payments::RegisterPayment` queda en codebase pero sin callers (deprecated).

### Sales ledger

* **`SalesLedger::ImportCsv`** writes import batches + ledger entries; it **does not** create **`Order`**, **`StockMovement`**, or **`Payment`** (see comments in the service).

---

## Key constraints

* Do **not** bump **`products.current_stock`** ad hoc in controllers/views — keep stock changes through **`StockMovement`** + **`#recalculate_current_stock!`** as the code already does in services.
* **Validate stock before selling** — enforced in **`Sales::CreateOrder`** against **`current_stock`**.
* **Un `Payment` representa un tender** con método único; su distribución sobre órdenes vive en `payment_allocations`. **`Customer#current_balance`** = sum(credit orders confirmadas `total_amount`) − sum(`payment_allocations` sobre esas credit orders). Los Payments asignados a ventas `immediate` no afectan el balance.
* **`Customer` validation:** `retail` customers cannot have `has_credit_account: true` (`retail_cannot_have_credit_account`).
* **`Order` validation:** `paper_number` is required when `source: 'from_paper'`; stock validation is skipped for `from_paper` orders.
* Not every HTTP action uses a service: e.g. **pending invoice cancel** and **credit note** CRUD use **`update` / `save` / `destroy`** on models directly.

---

## Active services (called from app code paths)

* **Sales:** `Sales::CreateOrder`, `Sales::CancelOrder`
* **Inventory:** `Inventory::AdjustStock`
* **Invoices:** `Invoices::CreateSimpleInvoice`, `Invoices::MarkAsPaid`, `Invoices::ProcessPayment`
* **Payments:** `Payments::AllocatePayment`
* **Sales ledger:** `SalesLedger::ImportCsv`; report query objects under **`SalesLedger::Reports::`** (from `Web::SalesLedger::ReportsController`)

**Present in codebase but not wired to `Web::` controllers:** `Purchasing::CreatePurchase`, `Purchasing::CancelPurchase`, **`Inventory::SyncFromCsv`** (invoked from **`lib/tasks/inventory.rake`**, not from HTTP), **`Payments::RegisterPayment`** (deprecated — superseded by `Payments::AllocatePayment`).

---

## Important gaps

* **`Payment` / `PaymentAllocation`** web UI under `web/customers/:customer_id/payments` (new/create only) usa `Payments::AllocatePayment`; permite distribuir un cobro entre varias órdenes con método de pago independiente por fila.
* **No web UI** for itemized purchasing: **`Purchasing::CreatePurchase`** is used in **seeds/specs**, not `Web::InvoicesController`.
* **`Inventory::SyncFromCsv`** is **rake-only**, not exposed in routes.

---

## Notes

* For behavior, **read the service (or controller action) in question** — “thin controller” is the norm for orders and ledger imports, but invoices/credit notes mix services and direct updates.
