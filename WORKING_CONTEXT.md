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
* **Orders**: index/show/new/create; member **POST `cancel`** → `Sales::CancelOrder`. Create builds items from **`purchase_items`** params and resolves customer via **`Customer.mostrador`** when `customer_id` is blank or `"mostrador"`.
* **Customers**: index/show/new/create/edit/update; nested **`payments`** new/create → `Payments::RegisterPayment` (module `Web::Customers`).
* **Suppliers**: full `resources` (includes destroy).
* **Invoices**: simple-mode UI only (see below): index/new/create/show/edit/update; **`pending`** list; **`mark_supplier_paid`**; member **`mark_as_paid`**, **`cancel`** (pending invoice → `cancelled` via controller `update`, no service).
* **Credit notes**: full CRUD + **`supplier_invoices`** JSON for pending simple invoices by supplier — **direct ActiveRecord** in the controller (no dedicated service class).
* **Sales ledger**: **`imports`** index/create/show → `SalesLedger::ImportCsv`; **`reports#index`** → `SalesLedger::Reports::{SummaryQuery,SalesByDateQuery,TopProductsQuery}`. All three queries accept an optional **`product_source`** filter (`local` / `importado`), validated in the controller against `Entry::PRODUCT_SOURCES` before use. `TopProductsQuery` ranks by **frequency** (`COUNT(DISTINCT ticket_number)`) not quantity, returns top 15, and exposes `product_source` via `MIN(product_source)` in the SELECT.

---

## Core flows

### Orders

* `order_type` enum values: **`immediate`** (was `cash`) and **`credit`**. `cash` is reserved for payment methods.
* Created via **`Sales::CreateOrder`** (from `Web::OrdersController#create`).
* Cancelled via **`Sales::CancelOrder`** (member cancel).
* Confirmed sales create **`StockMovement`** rows with **`movement_type: sale`** via **`Inventory::AdjustStock`** (signed quantity: **outbound is negative** in the implemented paths).
* **`Sales::CancelOrder`** restocks using **`Inventory::AdjustStock`** with **`movement_type: adjustment`** and a **positive** quantity per line (not a second `sale` movement).

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

### Customer account payments (`Payment` model)

* **`Payments::RegisterPayment`** creates a **`Payment`** tied only to **`customer`** (no `order_id`); **`Payment`** validates **`has_credit_account`** on the customer.
* **`Sales::CreateOrder`** acepta `initial_payment: { amount:, payment_method: }` opcional para órdenes `credit`. Cuando viene, crea un **`Payment`** con `order_id` apuntando a la orden, dentro de la misma transacción.
* **`Sales::CancelOrder`** destruye los **`Payment`** asociados a la orden (`@order.payments.destroy_all`) dentro de su transacción.
* **`Web::Customers::PaymentsController`** registra pagos sueltos al cliente (`order_id: nil`).

### Sales ledger

* **`SalesLedger::ImportCsv`** writes import batches + ledger entries; it **does not** create **`Order`**, **`StockMovement`**, or **`Payment`** (see comments in the service).

---

## Key constraints

* Do **not** bump **`products.current_stock`** ad hoc in controllers/views — keep stock changes through **`StockMovement`** + **`#recalculate_current_stock!`** as the code already does in services.
* **Validate stock before selling** — enforced in **`Sales::CreateOrder`** against **`current_stock`**.
* **Los `Payment` pueden estar atados a una `Order` (cobros iniciales de venta) o ser sueltos (`order_id: nil`, abonos de cuenta corriente)**; **`Customer#current_balance`** se sigue derivando de credit **`Order`** totals minus **`payments`** (ambos casos cuentan).
* **`Customer` validation:** `retail` customers cannot have `has_credit_account: true` (`retail_cannot_have_credit_account`).
* **`Order` validation:** `paper_number` is required when `source: 'from_paper'`; stock validation is skipped for `from_paper` orders.
* Not every HTTP action uses a service: e.g. **pending invoice cancel** and **credit note** CRUD use **`update` / `save` / `destroy`** on models directly.

---

## Active services (called from app code paths)

* **Sales:** `Sales::CreateOrder`, `Sales::CancelOrder`
* **Inventory:** `Inventory::AdjustStock`
* **Invoices:** `Invoices::CreateSimpleInvoice`, `Invoices::MarkAsPaid`, `Invoices::ProcessPayment`
* **Payments:** `Payments::RegisterPayment`
* **Sales ledger:** `SalesLedger::ImportCsv`; report query objects under **`SalesLedger::Reports::`** (from `Web::SalesLedger::ReportsController`)

**Present in codebase but not wired to `Web::` controllers:** `Purchasing::CreatePurchase`, `Purchasing::CancelPurchase`, **`Inventory::SyncFromCsv`** (invoked from **`lib/tasks/inventory.rake`**, not from HTTP).

---

## Important gaps

* **`Payment`** / `Payments::RegisterPayment` now has web UI under `web/customers/:customer_id/payments` (new/create only).
* **No web UI** for itemized purchasing: **`Purchasing::CreatePurchase`** is used in **seeds/specs**, not `Web::InvoicesController`.
* **`Inventory::SyncFromCsv`** is **rake-only**, not exposed in routes.

---

## Notes

* For behavior, **read the service (or controller action) in question** — “thin controller” is the norm for orders and ledger imports, but invoices/credit notes mix services and direct updates.
