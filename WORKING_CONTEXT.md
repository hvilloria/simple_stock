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
* **Products**: index/show/new/create + collection **`search`**; nested **`stock_movements`** new/create → `Inventory::AdjustStock` (stock location = **`StockLocation.first!`**). **`edit`/`update` implementados** (`admin` + `vendedor` vía `ProductPolicy`; `caja` no). El `_form` postea a `create` o `update` según `product.persisted?`. Editable todo lo que el form renderiza **menos `sku`** (readonly, ancla de identidad OEM) y **`current_stock`** (va por movimientos). Cambiar `origin`/`product_type`/`brand` puede chocar con la unicidad de variante (validación del modelo) → error en el form. El precio editado es el "próximo default": el **write-back** de cada venta lo puede pisar (ver "Precio manual + write-back").
* **Orders**: index/show/new/create; member **POST `cancel`** → `Sales::CancelOrder`. Create builds items from **`purchase_items`** params and resolves customer via **`Customer.mostrador`** when `customer_id` is blank or `"mostrador"`. El form `new` muestra solo Cliente · Tipo · N° Talonario · Productos (sin "Descuento" ni "Detalle de Pago"). Submit habilita con items + customer + paper_number.
* **Customers**: index/show/new/create/edit/update; **`debtors`** collection → lista de clientes con balance > 0 ordenada por deuda; nested **`payments`** new/create → `Payments::AllocatePayment` (module `Web::Customers`). El form de cobro permite distribuir el pago entre una o varias órdenes pendientes con método de pago independiente por fila.
* **Sale notes** (caja): index + cancel + nested payment new/create. `Web::SaleNotesController#index` lista `Order.immediate.pending`; `Web::SaleNotes::PaymentsController` cobra vía `Payments::CollectSaleNote` (descuento global 0/5/10, multi-tender, regla cash-only). Sidebar entry "Notas de pedido" visible para caja+admin con badge de pendientes.
* **Payments on account** (pago a cuenta): `resources :payments_on_account` index/show + member **POST `deliver`** + nested payment new/create. `Web::PaymentsOnAccountController#index` lista `Order.open_on_account` (no liquidadas) con búsqueda por contacto (`search_contact`); `#show` es la vista del vendedor (marca entregas); `#deliver` → `Inventory::MarkDelivered`. `Web::PaymentsOnAccount::PaymentsController` cobra vía `Payments::CollectOnAccount`. Roles vía `PaymentOnAccountPolicy`: ver lista/detalle = vendedor+caja+admin, marcar entrega = vendedor+admin, cobrar = caja+admin (en `show` los controles se gatean con `@can_deliver` / `@can_collect`). Sidebar entry "Pagos a cuenta" visible para los tres roles con badge de operaciones abiertas.
* **Suppliers**: full `resources` (includes destroy).
* **Invoices**: simple-mode UI only (see below): index/new/create/show/edit/update; **`pending`** list; **`mark_supplier_paid`**; member **`mark_as_paid`**, **`cancel`** (pending invoice → `cancelled` via controller `update`, no service).
* **Credit notes**: full CRUD + **`supplier_invoices`** JSON for pending simple invoices by supplier — **direct ActiveRecord** in the controller (no dedicated service class).
* **Sales ledger**: **`imports`** index/create/show → `SalesLedger::ImportCsv`; **`reports#index`** → `SalesLedger::Reports::{SummaryQuery,SalesByDateQuery,TopProductsQuery}`. All three queries accept an optional **`product_source`** filter (`local` / `importado`), validated in the controller against `Entry::PRODUCT_SOURCES` before use. `TopProductsQuery` ranks by **frequency** (`COUNT(DISTINCT ticket_number)`) not quantity, returns top 15, and exposes `product_source` via `MIN(product_source)` in the SELECT.

---

## Core flows

### Orders

* `order_type` enum: `immediate`, `credit` y `on_account` (ver "Pagos a cuenta" abajo). `status` enum: `pending`, `confirmed`, `cancelled` (default `pending`). Orders nacen `pending`; promueven a `confirmed` automáticamente cuando `outstanding_balance == 0` vía `Order#refresh_status_from_balance!` (llamado desde `Payments::AllocatePayment`, `Payments::CollectSaleNote` y `Payments::CollectOnAccount` al final de la transacción).
* Created via `Sales::CreateOrder` (from `Web::OrdersController#create`). Solo recibe `customer:, items:, order_type:, paper_number:, channel:, source:, sale_date:`. **No captura pagos ni descuento** — el vendedor genera una nota; caja la cobra después (immediate) o entra a cuentas por cobrar (credit).
* `paper_number` es **obligatorio para toda nota** (live y from_paper).
* El form `new` muestra Cliente · Tipo · N° Talonario · Productos (sin "Descuento" ni "Detalle de Pago"). Cada renglón tiene **precio unitario editable** (input `currency-input`, formato AR `1.500.000,50`, prefilled con `product.price_unit`). Submit habilita con items + customer + paper_number + **todos los precios > 0**.
* **Precio manual + write-back:** `Sales::CreateOrder` exige `unit_price > 0` para **cada** item, en **todos** los `source` (ya no tolera nil/0 — el viejo modo `from_paper` con precio nulo dejó de existir). Al crear la orden, escribe el precio tipeado de vuelta en `product.price_unit` dentro de la misma transacción, así futuras ventas arrancan con ese precio. `price_unit` no está protegido como el stock/costo, así que el `update!` directo es el mecanismo correcto.
* Cancelled via `Sales::CancelOrder` (member cancel). `OrderPolicy#cancel_pending?` permite vendedor/caja/admin sobre notas `pending`; `#cancel?` solo admin sobre `confirmed`. El controller elige la policy method según el estado.

#### Precio local vs importado (decisión 2026-06-26)

* **Resolución del problema "un mismo repuesto tiene dos precios según el origen del lote".** Se **descartó** la lista de precios por origen (un solo producto con tarifas local/importada) y todas las variantes con doble precio. **No hay tarifa local/importada elegible al cobrar ni costos separados por origen** — la mejora fina queda para más adelante.
* **Mecanismo adoptado (ya cubierto por el comportamiento existente):**
  1. **El precio se setea manualmente en cada venta** — precio por renglón editable en `web/orders/new` + **write-back** a `product.price_unit` (ver "Precio manual + write-back" arriba). El precio de catálogo se va ajustando con cada venta; eso es **intencional**, no un bug.
  2. **El precio se puede editar** desde la pantalla de producto (`web/products/:id/edit`, admin+vendedor), pero esa edición fija el "próximo default" — el **write-back** de la siguiente venta lo puede pisar. `current_stock` sigue sin editarse (movimientos); `cost_unit` es editable pero `recalculate_average_cost!` lo recalcula al confirmar compras.
  3. **Cambio de origen** (ej. importado USA agotado → recompra local/china): **mejor caso**, se crea un **producto nuevo** con ese `origin` (variante por `sku + product_type + origin + brand`); **peor caso**, el próximo precio de venta simplemente pisa el `price_unit` del producto existente vía write-back.
* **Limitación honesta asumida:** el `cost_unit` sigue siendo un promedio que mezcla compras locales e importadas, así que el margen por origen no es exacto. No empeora respecto de hoy.
* **Stock no se modifica al vender hoy** — `Sales::CreateOrder` no crea `StockMovement`. La validación de disponibilidad corre **solo en `source: 'live'`**; el form `web/orders/new` envía **`source: from_paper` por defecto**, así que en la práctica **no se valida stock al vender** (se pueden agregar productos sin stock y cantidades libres; ver Key constraints). `Sales::CancelOrder` sí restockea vía `Inventory::AdjustStock` (asimétrico — comportamiento pre-existente, no parte de este feature).
* Descuento de inmediatas: caja lo aplica al cobrar vía `Payments::CollectSaleNote`. Cap `0 / 5 / 10` (global), distribuido a todos los `order_items`. **Regla:** solo permitido si la totalidad se paga en efectivo (validado en backend y enforced en Stimulus). **Redondeo ceil-a-100 (efectivo con descuento):** cuando hay descuento (>0), el efectivo a cobrar = `original_total × (1 − desc/100)` redondeado **hacia arriba al múltiplo de 100** vía `Payments::CashRounding#round_up_to_hundred` (ej. `710.775 × 0,90 = 639.697,5 → 639.700`). `apply_discount!` setea `total_amount = effective_total` (el valor redondeado canónico); `order_item.discount_percent` queda como metadato de display. Sin descuento: exacto, sin redondeo. El front (`sale_note_payment_controller`) usa el mismo `Math.ceil(raw/100)*100`.
* Descuento de credit: sin cambios respecto a feat_09 (per-item 0-20% en primer cobro vía `Payments::AllocatePayment`; congelado tras la primera allocation).

### Pagos a cuenta (`on_account`)

* Tercer `order_type`: **`on_account`** — venta de mostrador que se paga en cuotas y se entrega progresivamente. Nace `pending`; promueve a `confirmed` cuando `outstanding_balance == 0`.
* **Contacto obligatorio** (solo este tipo): columnas `contact_name` / `contact_phone` en `orders`, validadas en `Order#on_account_requires_contact` y en `Sales::CreateOrder`. El cliente asociado queda como Mostrador; **no** entra en `Customer#current_balance` (la fórmula solo cuenta `credit`).
* **Entrega por ítem**: columna `order_items.delivered_at` (nullable). La marca el **vendedor**, no caja: al crear (`Sales::CreateOrder` con `delivered_product_ids`) y después desde el detalle vía `Inventory::MarkDelivered` (member `POST deliver`). **No genera `StockMovement`** todavía.
* **Liquidada** (sale de la lista de abiertas) solo con `outstanding_balance == 0` **y** todos los ítems con `delivered_at` (`Order#settled?` / `#fully_delivered?`). Scope `Order.open_on_account` (Postgres `HAVING`: saldo > 0 **OR** ítems sin entregar). Búsqueda por contacto: `Order.search_contact`.
* **Cobro parcial repetible** vía `Payments::CollectOnAccount` (hermano de `CollectSaleNote`). Recibe `order:, amount_to_settle:, discount_percent:, tenders:`. `amount_to_settle` = cuánto del saldo cancela esta visita (guard duro `≤ outstanding_balance`). Descuento por evento `0/5/10`, **solo efectivo**. **Redondeo ceil-a-100 (efectivo con descuento):** el efectivo a cobrar (`cash_to_collect`) = `amount_to_settle × (1 − desc/100)` redondeado **hacia arriba al múltiplo de 100** (`Payments::CashRounding#round_up_to_hundred`); sin descuento, exacto. `apply_discount!` **baja `total_amount`** por el **descuento efectivo** = `amount_to_settle − cash_to_collect` (NO por el descuento nominal), así el saldo cierra exacto contra la allocation redondeada (`original_total_amount` intacto). La `PaymentAllocation` registra el efectivo redondeado. El controller (`Web::PaymentsOnAccount::PaymentsController`) arma el tender con el **mismo** valor redondeado (`(cash_raw / 100.0).ceil * 100` cuando `discount > 0`). Llama `refresh_status_from_balance!` al final. **Para montos de spec usar descuento nominal ≥ 100** (evita que el ceil trepe `cash_to_collect` por encima de `amount_to_settle`).
* Pantalla de cobro: el form envía `amount_to_settle` (precargado con el saldo) + `payment_method` (medio único, sin monto) + `discount_percent`; el controller deriva el efectivo y arma el tender. **"A cobrar" (efectivo) es el único monto que cobra caja**; "Cancela de la cuenta" es informativo. Entrega visible **solo lectura** en esta pantalla.

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

* **`Payment`** representa un *tender* (entrega física de dinero con un método único). Pertenece al `customer`; **ya no tiene `order_id`**. Validaciones: `amount > 0`, `payment_method ∈ Payment::PAYMENT_METHODS` (fuente única: `PAYMENT_METHOD_LABELS` en `app/models/payment.rb` → `cash bank_qr bank_card bank_transfer mercado_pago`; etiquetas vía `Payment.method_label` / opciones de UI vía `Payment.method_options`), `payment_date presente`. **Ya no exige `has_credit_account?`** — los Payments pueden pertenecer a clientes retail (mostrador).
* **`PaymentAllocation`** (join `payment_allocations(payment_id, order_id, amount)`) distribuye el monto de un Payment sobre una o varias órdenes. Validaciones: `amount > 0`, `order_belongs_to_payment_customer`, `amount_within_order_outstanding_balance` (con `where.not(id: id)` para excluir la allocation actual). Índice único `(payment_id, order_id)`.
* **Invariante:** `payment.amount == SUM(payment.allocations.amount)` — garantizada por el servicio, no por una validación de modelo.
* **`Payments::AllocatePayment`** servicio del cobro de credit. Recibe `customer:, payment_date:, notes:, allocations: [{order_id:, amount:, payment_method:, item_discounts: {oi_id => percent}}]`. Acepta órdenes `pending` o `confirmed` (rechaza solo `cancelled`). Agrupa por `payment_method`, crea un `Payment` por grupo + sus `PaymentAllocation`s, y llama `refresh_status_from_balance!` en cada orden tocada al final de la transacción. **El redondeo ceil-a-100 en efectivo con descuento es SOLO front** (`payment_allocation_controller#recomputeCard` precarga el monto a cobrar redondeado cuando el método es `cash` y hay descuento): el backend **no** lo enforça, porque los pagos parciales de crédito deben poder ser de monto libre (decisión del usuario).
* **`Sales::CancelOrder`** destruye las `PaymentAllocation` de la orden cancelada (`@order.payment_allocations.destroy_all`); los `Payment` **quedan vivos** (known limitation — pueden quedar huérfanos sin asignación, el `current_balance` del cliente los sigue descontando como crédito a favor).
* `Order#outstanding_balance` = `total_amount − payment_allocations.sum(:amount)` para órdenes no canceladas (cualquier tipo). Promoción automática a `confirmed` cuando llega a 0 vía `Order#refresh_status_from_balance!`, invocado desde `Payments::AllocatePayment` y `Payments::CollectSaleNote` al final de la transacción.
* `Customer#current_balance` = `SUM(credit_orders.total_amount) − SUM(payment_allocations on credit orders)` filtrando `status IN ('pending', 'confirmed')`. `Customer.with_outstanding_balance` usa la misma fórmula. Las órdenes `on_account` (pago a cuenta) **no** entran: la fórmula solo cuenta `order_type: 'credit'`.
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
* **Manual pricing (`unit_price > 0`):** every order item must have a positive `unit_price` — enforced in **`Sales::CreateOrder`** for all sources, and in Stimulus (`order_form_controller`) by disabling submit while any line price is `<= 0`. Creating an order writes each typed price back to **`product.price_unit`** (catalog price for future sales) inside the transaction. `price_unit` is **not** a protected field like `current_stock`/`cost_unit`, so a direct `update!` is the correct mechanism.
* **Unicidad de productos (variantes):** la identidad de una variante es **`sku (OEM) + product_type + origin + brand`**. La **validación de modelo** (`Product`) enforça la unicidad **solo cuando `origin` está presente** (`if: -> { origin.present? }`), para permitir carga progresiva: se carga primero el origen y la **marca se afina después**; con `origin` en `nil` (importadores / carga cruda) no valida. El **índice DB** `index_products_on_variant_uniqueness` queda **lenient** (Postgres NULLS DISTINCT → no bloquea duplicados con `origin`/`brand` en `nil`): es **backstop para filas completas**, el **modelo es el enforcer real**. `sku` = código OEM (se repite entre variantes); `origin`/`brand` son nullable.
* Not every HTTP action uses a service: e.g. **pending invoice cancel** and **credit note** CRUD use **`update` / `save` / `destroy`** on models directly.
* **Fechas/horas timezone-aware** — usar siempre **`Date.current` / `Time.current`**, nunca `Date.today` / `Time.now`. La app corre en **UTC** (no hay `config.time_zone`); `Date.today` toma la zona del SO y produce off-by-one cerca de medianoche (causó tests flaky en `Invoice`/`Customer`). Todo el código y los specs usan `Date.current`.

---

## Active services (called from app code paths)

* **Sales:** `Sales::CreateOrder`, `Sales::CancelOrder`
* **Inventory:** `Inventory::AdjustStock`, `Inventory::MarkDelivered`
* **Invoices:** `Invoices::CreateSimpleInvoice`, `Invoices::MarkAsPaid`, `Invoices::ProcessPayment`
* **Payments:** `Payments::AllocatePayment`, `Payments::CollectSaleNote`, `Payments::CollectOnAccount`
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
