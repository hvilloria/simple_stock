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
* **Products**: index/show/new/create + collection **`search`**; nested **`stock_movements`** new/create → `Inventory::AdjustStock` (stock location = **`StockLocation.first!`**). **`edit`/`update` implemented** (`admin` + `vendedor` via `ProductPolicy`; `caja` not). The `_form` posts to `create` or `update` depending on `product.persisted?`. Everything the form renders is editable **except `sku`** (readonly, OEM identity anchor) and **`current_stock`** (goes through movements). Changing `origin`/`product_type`/`brand` may collide with variant uniqueness (model validation) → error in the form. The edited price is the "next default": the **write-back** of each sale can overwrite it (see "Manual pricing + write-back").
* **Orders**: index/show/new/create; member **POST `cancel`** → `Sales::CancelOrder`. Create builds items from **`purchase_items`** params and resolves customer via **`Customer.mostrador`** when `customer_id` is blank or `"mostrador"`. The `new` form shows only Customer · Type · Paper Number · Products (no "Discount" or "Payment Detail"). Submit enables with items + customer + paper_number.
* **Customers**: index/show/new/create/edit/update; **`debtors`** collection → list of customers with balance > 0 ordered by debt; nested **`payments`** new/create → `Payments::AllocatePayment` (module `Web::Customers`). The collection form lets you distribute the payment across one or several pending orders with an independent payment method per row.
* **Sale notes** (caja): index + cancel + nested payment new/create. `Web::SaleNotesController#index` lists `Order.immediate.pending`; `Web::SaleNotes::PaymentsController` collects via `Payments::CollectSaleNote` (global discount 0/5/10, multi-tender, cash-only rule). Sidebar entry "Notas de pedido" visible to caja+admin with a pending-count badge.
* **Payments on account** (pago a cuenta): `resources :payments_on_account` index/show + member **POST `deliver`** + nested payment new/create. `Web::PaymentsOnAccountController#index` lists `Order.open_on_account` (not settled) with search by contact (`search_contact`); `#show` is the vendor's view (marks deliveries); `#deliver` → `Inventory::MarkDelivered`. `Web::PaymentsOnAccount::PaymentsController` collects via `Payments::CollectOnAccount`. Roles via `PaymentOnAccountPolicy`: view list/detail = vendedor+caja+admin, mark delivery = vendedor+admin, collect = caja+admin (in `show` the controls are gated with `@can_deliver` / `@can_collect`). Sidebar entry "Pagos a cuenta" visible to all three roles with a badge of open operations.
* **Suppliers**: full `resources` (includes destroy).
* **Invoices**: simple-mode UI only (see below): index/new/create/show/edit/update; **`pending`** list; **`mark_supplier_paid`**; member **`mark_as_paid`**, **`cancel`** (pending invoice → `cancelled` via controller `update`, no service).
* **Credit notes**: full CRUD + **`supplier_invoices`** JSON for pending simple invoices by supplier — **direct ActiveRecord** in the controller (no dedicated service class).
---

## Core flows

### Orders

* `order_type` enum: `immediate`, `credit` and `on_account` (see "Payments on account" below). `status` enum: `pending`, `confirmed`, `cancelled` (default `pending`). Orders are born `pending`; they promote to `confirmed` automatically when `outstanding_balance == 0` via `Order#refresh_status_from_balance!` (called from `Payments::AllocatePayment`, `Payments::CollectSaleNote` and `Payments::CollectOnAccount` at the end of the transaction).
* Created via `Sales::CreateOrder` (from `Web::OrdersController#create`). It only receives `customer:, items:, order_type:, paper_number:, channel:, source:, sale_date:`. **It captures neither payments nor discount** — the vendor generates a note; caja collects it later (immediate) or it enters accounts receivable (credit).
* `paper_number` is **required for every note** (live and from_paper).
* The `new` form shows Customer · Type · Paper Number · Products (no "Discount" or "Payment Detail"). Each line has an **editable unit price** (`currency-input` input, AR format `1.500.000,50`, prefilled with `product.price_unit`). Submit enables with items + customer + paper_number + **all prices > 0**.
* **Manual pricing + write-back:** `Sales::CreateOrder` requires `unit_price > 0` for **every** item, in **all** `source` values (it no longer tolerates nil/0 — the old `from_paper` mode with a null price no longer exists). When creating the order, it writes the typed price back into `product.price_unit` within the same transaction, so future sales start from that price. `price_unit` is not protected like stock/cost, so a direct `update!` is the correct mechanism.
* Cancelled via `Sales::CancelOrder` (member cancel). `OrderPolicy#cancel_pending?` allows vendedor/caja/admin on `pending` notes; `#cancel?` only admin on `confirmed`. The controller picks the policy method based on the state.

#### Local vs imported price (decision 2026-06-26)

* **Resolution of the problem "the same part has two prices depending on the batch's origin".** The per-origin price list (a single product with local/imported rates) and all dual-price variants were **discarded**. **There is no selectable local/imported rate at collection time nor costs separated by origin** — the fine-grained improvement is left for later.
* **Adopted mechanism (already covered by existing behavior):**
  1. **The price is set manually on each sale** — editable per-line price in `web/orders/new` + **write-back** to `product.price_unit` (see "Manual pricing + write-back" above). The catalog price adjusts with each sale; that is **intentional**, not a bug.
  2. **The price can be edited** from the product screen (`web/products/:id/edit`, admin+vendedor), but that edit sets the "next default" — the **write-back** of the next sale can overwrite it. `current_stock` still cannot be edited (movements); `cost_unit` is editable but `recalculate_average_cost!` recomputes it when purchases are confirmed.
  3. **Origin change** (e.g. imported USA sold out → local/china repurchase): **best case**, a **new product** is created with that `origin` (variant by `sku + product_type + origin + brand`); **worst case**, the next sale price simply overwrites the existing product's `price_unit` via write-back.
* **Honest assumed limitation:** `cost_unit` is still an average that mixes local and imported purchases, so the margin by origin is not exact. It does not get worse than today.
* **Stock is not modified when selling today** — `Sales::CreateOrder` does not create a `StockMovement`. The availability validation runs **only on `source: 'live'`**; the `web/orders/new` form submits **`source: from_paper` by default**, so in practice **stock is not validated when selling** (products with no stock and arbitrary quantities can be added; see Key constraints). `Sales::CancelOrder` does restock via `Inventory::AdjustStock` (asymmetric — pre-existing behavior, not part of this feature).
* Immediate discount: caja applies it at collection time via `Payments::CollectSaleNote`. Cap `0 / 5 / 10` (global), distributed across all `order_items`. **Rule:** only allowed if the whole amount is paid in cash (validated in the backend and enforced in Stimulus). **Ceil-to-100 rounding (cash with discount):** when there is a discount (>0), the cash to collect = `original_total × (1 − desc/100)` rounded **up to the nearest multiple of 100** via `Payments::CashRounding#round_up_to_hundred` (e.g. `710.775 × 0,90 = 639.697,5 → 639.700`). `apply_discount!` sets `total_amount = effective_total` (the canonical rounded value); `order_item.discount_percent` remains as display metadata. Without discount: exact, no rounding. The front end (`sale_note_payment_controller`) uses the same `Math.ceil(raw/100)*100`.
* **Discount display (`web/orders/show`):** the discount and the rounding are shown as **two separate lines** so they are not confused. `Order#discount_amount` is the **nominal** discount (sum of `qty × unit × discount_percent/100` per item), **not** `original − total` — deriving it from the total would mix the ceil with the discount (historical bug: with `total_amount` already rounded, `original − total` gave 2.400 instead of the real 10% of 2.450). `Order#rounding_amount` = `total_amount − (original_total_amount − discount_amount)` exposes the ceil-to-100 charge separately (0 when there was no rounding, e.g. per-item credit discounts). It reconciles: `Subtotal − Discount + Rounding = Total`. `total_amount` remains the canonical rounded value (the `payment_allocations` close exactly).
* Credit discount: unchanged with respect to feat_09 (per-item 0-20% on the first collection via `Payments::AllocatePayment`; frozen after the first allocation).

### Payments on account (`on_account`)

* Third `order_type`: **`on_account`** — a counter sale that is paid in installments and delivered progressively. Born `pending`; promotes to `confirmed` when `outstanding_balance == 0`.
* **Contact required** (this type only): `contact_name` / `contact_phone` columns in `orders`, validated in `Order#on_account_requires_contact` and in `Sales::CreateOrder`. The associated customer stays as Mostrador; it does **not** enter `Customer#current_balance` (the formula only counts `credit`).
* **Per-item delivery**: `order_items.delivered_at` column (nullable). It is marked by the **vendedor**, not caja: at creation (`Sales::CreateOrder` with `delivered_product_ids`) and later from the detail view via `Inventory::MarkDelivered` (member `POST deliver`). It does **not generate a `StockMovement`** yet.
* **Settled** (leaves the open list) only with `outstanding_balance == 0` **and** all items with `delivered_at` (`Order#settled?` / `#fully_delivered?`). Scope `Order.open_on_account` (Postgres `HAVING`: balance > 0 **OR** undelivered items). Search by contact: `Order.search_contact`.
* **Repeatable partial collection** via `Payments::CollectOnAccount` (sibling of `CollectSaleNote`). It receives `order:, amount_to_settle:, discount_percent:, tenders:`. `amount_to_settle` = how much of the balance this visit cancels (hard guard `≤ outstanding_balance`). Per-event discount `0/5/10`, **cash only**. **Ceil-to-100 rounding (cash with discount):** the cash to collect (`cash_to_collect`) = `amount_to_settle × (1 − desc/100)` rounded **up to the nearest multiple of 100** (`Payments::CashRounding#round_up_to_hundred`); without discount, exact. `apply_discount!` **lowers `total_amount`** by the **effective discount** = `amount_to_settle − cash_to_collect` (NOT by the nominal discount), so the balance closes exactly against the rounded allocation (`original_total_amount` untouched). The `PaymentAllocation` records the rounded cash. The controller (`Web::PaymentsOnAccount::PaymentsController`) builds the tender with the **same** rounded value (`(cash_raw / 100.0).ceil * 100` when `discount > 0`). It calls `refresh_status_from_balance!` at the end. **For spec amounts use a nominal discount ≥ 100** (avoids the ceil pushing `cash_to_collect` above `amount_to_settle`).
* Collection screen: the form submits `amount_to_settle` (preloaded with the balance) + `payment_method` (single method, no amount) + `discount_percent`; the controller derives the cash and builds the tender. **"To collect" (cash) is the only amount caja charges**; "Cancels from the account" is informational. Delivery visible **read-only** on this screen.

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
* **Credit-note availability** = `CreditNote#available?` (`active_status? && !exhausted?`), **not** the `available`/`where(status: "active")` scope. The `status` enum is only `active`/`cancelled`; a fully-applied note stays `active` but is **exhausted** (`remaining_balance <= 0`). For *count* metrics use `.count(&:available?)` so exhausted notes are excluded (they already contribute 0 to amount sums via `remaining_balance`). Applies to invoices index (`@credit_notes_count`), credit-notes index, and `Supplier#credit_notes_count`.

### Customer account payments (`Payment` + `PaymentAllocation` models)

* **`Payment`** represents a *tender* (a physical delivery of money with a single method). It belongs to the `customer`; **it no longer has `order_id`**. Validations: `amount > 0`, `payment_method ∈ Payment::PAYMENT_METHODS` (single source: `PAYMENT_METHOD_LABELS` in `app/models/payment.rb` → `cash bank_qr bank_card bank_transfer mercado_pago`; labels via `Payment.method_label` / UI options via `Payment.method_options`), `payment_date` present. **It no longer requires `has_credit_account?`** — Payments can belong to retail (mostrador) customers.
* **`PaymentAllocation`** (join `payment_allocations(payment_id, order_id, amount)`) distributes a Payment's amount across one or several orders. Validations: `amount > 0`, `order_belongs_to_payment_customer`, `amount_within_order_outstanding_balance` (with `where.not(id: id)` to exclude the current allocation). Unique index `(payment_id, order_id)`.
* **Invariant:** `payment.amount == SUM(payment.allocations.amount)` — guaranteed by the service, not by a model validation.
* **`Payments::AllocatePayment`** service for credit collection. It receives `customer:, payment_date:, notes:, allocations: [{order_id:, amount:, payment_method:, item_discounts: {oi_id => percent}}]`. It accepts `pending` or `confirmed` orders (rejects only `cancelled`). It groups by `payment_method`, creates one `Payment` per group + its `PaymentAllocation`s, and calls `refresh_status_from_balance!` on each touched order at the end of the transaction. **The ceil-to-100 rounding for cash with discount is FRONT-END ONLY** (`payment_allocation_controller#recomputeCard` preloads the rounded amount to collect when the method is `cash` and there is a discount): the backend does **not** enforce it, because partial credit payments must be allowed to be of a free amount (user decision).
* **`Sales::CancelOrder`** destroys the `PaymentAllocation`s of the cancelled order (`@order.payment_allocations.destroy_all`); the `Payment`s **stay alive** (known limitation — they can end up orphaned with no allocation, and the customer's `current_balance` keeps discounting them as credit in their favor).
* `Order#outstanding_balance` = `total_amount − payment_allocations.sum(:amount)` for non-cancelled orders (any type). Automatic promotion to `confirmed` when it reaches 0 via `Order#refresh_status_from_balance!`, invoked from `Payments::AllocatePayment` and `Payments::CollectSaleNote` at the end of the transaction.
* `Customer#current_balance` = `SUM(credit_orders.total_amount) − SUM(payment_allocations on credit orders)` filtering `status IN ('pending', 'confirmed')`. `Customer.with_outstanding_balance` uses the same formula. `on_account` (payment on account) orders do **not** enter: the formula only counts `order_type: 'credit'`.
* **`Customer#last_payment_date`** / **`#days_without_paying`** — helpers for the debtors view.
* **`Customer.with_outstanding_balance`** scope — customers whose confirmed credit sales exceed the total of their payments.
* **`Web::Customers::PaymentsController#new`** shows a table with all pending orders; each row has an inclusion checkbox, an editable amount, and its own payment method. The POST submit receives indexed `params[:allocations]` (`allocations[N][order_id|include|amount|payment_method]`) and delegates to `Payments::AllocatePayment`. Stimulus controller (`payment_allocation_controller.js`) recomputes the summary live and disables submit if no orders are checked.
* **`payments` table** no longer has the `order_id` column — the relation lives in `payment_allocations`.

---

## Key constraints

* Do **not** bump **`products.current_stock`** ad hoc in controllers/views — keep stock changes through **`StockMovement`** + **`#recalculate_current_stock!`** as the code already does in services.
* **Validate stock before selling (`live` source only)** — enforced in **`Sales::CreateOrder`** against **`current_stock`**; the UI flow defaults to `from_paper`, which skips this (see Order validation below).
* **A `Payment` represents a tender** with a single method; its distribution over orders lives in `payment_allocations`. **`Customer#current_balance`** = sum(confirmed credit orders `total_amount`) − sum(`payment_allocations` over those credit orders). Payments allocated to `immediate` sales do not affect the balance.
* **`Customer` validation:** `retail` customers cannot have `has_credit_account: true` (`retail_cannot_have_credit_account`).
* **`Order` validation:** `paper_number` is **required for every order** (unconditional `presence: true`, not unique). `Sales::CreateOrder` validates stock availability for `source: 'live'` only; it skips the check for `from_paper`. **`web/orders/new` submits `source: from_paper` by default** (hidden field), so the UI sales flow does **not** validate stock at sale time — the vendor is trusted to know the product exists (no inventory system yet). The `live` branch and its stock validation remain in the service for future use.
* **Manual pricing (`unit_price > 0`):** every order item must have a positive `unit_price` — enforced in **`Sales::CreateOrder`** for all sources, and in Stimulus (`order_form_controller`) by disabling submit while any line price is `<= 0`. Creating an order writes each typed price back to **`product.price_unit`** (catalog price for future sales) inside the transaction. `price_unit` is **not** a protected field like `current_stock`/`cost_unit`, so a direct `update!` is the correct mechanism.
* **Product uniqueness (variants):** the identity of a variant is **`sku (OEM) + product_type + origin + brand`**. The **model validation** (`Product`) enforces uniqueness **only when `origin` is present** (`if: -> { origin.present? }`), to allow progressive loading: the origin is loaded first and the **brand is refined later**; with `origin` at `nil` (importers / raw load) it does not validate. The **DB index** `index_products_on_variant_uniqueness` stays **lenient** (Postgres NULLS DISTINCT → does not block duplicates with `origin`/`brand` at `nil`): it is a **backstop for complete rows**, the **model is the real enforcer**. `sku` = OEM code (repeated across variants); `origin`/`brand` are nullable.
* Not every HTTP action uses a service: e.g. **pending invoice cancel** and **credit note** CRUD use **`update` / `save` / `destroy`** on models directly.
* **Timezone-aware dates/times** — always use **`Date.current` / `Time.current`**, never `Date.today` / `Time.now`. The app runs in **UTC** (there is no `config.time_zone`); `Date.today` takes the OS zone and produces an off-by-one near midnight (caused flaky tests in `Invoice`/`Customer`). All code and specs use `Date.current`.

---

## Active services (called from app code paths)

* **Sales:** `Sales::CreateOrder`, `Sales::CancelOrder`
* **Inventory:** `Inventory::AdjustStock`, `Inventory::MarkDelivered`
* **Invoices:** `Invoices::CreateSimpleInvoice`, `Invoices::MarkAsPaid`, `Invoices::ProcessPayment`
* **Payments:** `Payments::AllocatePayment`, `Payments::CollectSaleNote`, `Payments::CollectOnAccount`
**Present in codebase but not wired to `Web::` controllers:** `Purchasing::CreatePurchase`, `Purchasing::CancelPurchase`, **`Inventory::SyncFromCsv`** (invoked from **`lib/tasks/inventory.rake`**, not from HTTP).

---

## Important gaps

* **`Payment` / `PaymentAllocation`** web UI under `web/customers/:customer_id/payments` (new/create only) uses `Payments::AllocatePayment`; it lets you distribute a collection across several orders with an independent payment method per row.
* **No web UI** for itemized purchasing: **`Purchasing::CreatePurchase`** is used in **seeds/specs**, not `Web::InvoicesController`.
* **`Inventory::SyncFromCsv`** is **rake-only**, not exposed in routes.

---

## Notes

* For behavior, **read the service (or controller action) in question** — “thin controller” is the norm for orders, but invoices/credit notes mix services and direct updates.
