# Customer Debt Visibility — Design Spec

**Date:** 2026-05-06
**Feature:** feat_05-customer-debt-visibility

## Context

The system currently tracks customer credit balances (`Customer#current_balance`) but provides no navigable view for operators to monitor outstanding debts. Additionally, several links in the UI are broken or missing:

- Order rows in `customers/show` are not clickable
- Customer links in `orders/show` point to `"#"`
- The sidebar has no link to the orders list (`web_orders_path`)
- A bug in `Payment#amount_within_order_total` compares against `order.total_amount` instead of the remaining outstanding balance, allowing overpayment on partially-paid orders

This feature fixes the above and adds a dedicated debt-tracking page for operators.

---

## Scope

### In scope

1. Bug fix: `Payment#amount_within_order_total` → compare against outstanding balance
2. New method: `Order#outstanding_balance`
3. New scope: `Customer.with_outstanding_balance`
4. Sidebar: add "Ventas del Sistema" link under the Ventas group; add "Cuentas por Cobrar" submenu under Clientes
5. `customers/index`: add saldo column for customers with credit account
6. `customers/show`: make credit order rows clickable; add Cobrado / Pendiente columns per order
7. `orders/show`: fix broken customer links (two locations)
8. New page `customers/debtors`: list of customers with balance > 0
9. Dashboard: link the receivables metric to the debtors page

### Out of scope

- Payment allocation to specific orders (each payment covers a single order) — deferred
- Many-to-many payment-to-order allocation — deferred
- Daily cash register (caja diaria) — separate feature
- System specs / browser tests

---

## Architecture

### No schema migrations required

All changes are additive methods and UI. The `order_id` column on `payments` already exists (added in feat_04). No new columns or tables.

### Backend changes

#### `Order#outstanding_balance`

```ruby
def outstanding_balance
  return 0 unless credit_order_type?
  total_amount - payments.sum(:amount)
end
```

Returns 0 for immediate orders. For credit orders, derives the remaining amount from linked payments. This is a computed value — no caching needed at current scale.

#### Fix `Payment#amount_within_order_total`

Current (buggy):
```ruby
if amount > order.total_amount
```

Fixed:
```ruby
def amount_within_order_total
  return if amount.nil? || order.nil? || order.total_amount.nil?
  existing_paid = order.payments.where.not(id: id).sum(:amount)
  remaining = order.total_amount - existing_paid
  if amount > remaining
    errors.add(:amount, "no puede exceder el saldo pendiente de la orden ($#{remaining})")
  end
end
```

The `where.not(id: id)` excludes the current record so the validation works correctly on both `create` and `update`.

#### `Customer.with_outstanding_balance` scope

```ruby
scope :with_outstanding_balance, -> {
  with_credit_account
    .where(
      "( SELECT COALESCE(SUM(o.total_amount), 0)
         FROM orders o
         WHERE o.customer_id = customers.id
           AND o.order_type = 'credit'
           AND o.status = 'confirmed' )
       >
       ( SELECT COALESCE(SUM(p.amount), 0)
         FROM payments p
         WHERE p.customer_id = customers.id )"
    )
}
```

Uses correlated subqueries to avoid a `GROUP BY` that would complicate chaining. Returns customers whose total confirmed credit orders exceed their total payments.

### Controller changes

#### `Web::CustomersController`

Add `debtors` action:

```ruby
def debtors
  authorize Customer, :debtors?
  @debtors = Customer
    .with_outstanding_balance
    .order(name: :asc)  # sorted by name; balance sorting done in view via helper or query
```

The balance sort requires either a subquery order or loading all records and sorting in Ruby. Given the expected scale (< 50 customers with credit), Ruby sort is acceptable:

```ruby
@debtors = Customer.with_outstanding_balance.to_a.sort_by { |c| -c.current_balance }
```

Add route:
```ruby
resources :customers, only: [...] do
  collection do
    get :debtors
  end
end
```

#### `CustomerPolicy`

Add `debtors?` — same permission as `index?`.

---

## UI

### Sidebar (`app/views/layouts/web/_sidebar.html.haml`)

**Ventas group** — add link to orders index as first submenu item:

```
Ventas
  ├── Ventas del Sistema  → web_orders_path
  ├── Ventas Importadas   → web_sales_ledger_imports_path (existing)
  └── Reportes            → web_sales_ledger_reports_path (existing)
```

**Clientes** — convert from single link to group with submenu:

```
Clientes
  ├── Todos los Clientes  → web_customers_path
  └── Cuentas por Cobrar  → debtors_web_customers_path  (badge: count of debtors)
```

The badge shows the count of `Customer.with_outstanding_balance`. It is loaded once per request via a helper or a `before_action` on `ApplicationController` that sets `@debtors_count`. To avoid an extra query on every page, scope the count to load only when the sidebar is rendered (it already is on every request — acceptable at current scale).

### `customers/index`

Add a "Saldo" column after "Cuenta Corriente". For customers without credit account, show `—`. For customers with credit account:
- Balance = 0 → green badge "Al día"
- Balance > 0 → amber text with formatted amount

Note: this requires calling `current_balance` per row. At current scale (< 20 customers) this is acceptable. If the list grows, add a counter cache or materialized column later.

### `customers/show`

**Credit orders table** — add two columns and make rows clickable:

| Fecha | Total | Cobrado | Pendiente | Estado |
|---|---|---|---|---|
| 15/04 | $400.000 | $250.000 | $150.000 | Pendiente |
| 01/04 | $200.000 | $200.000 | $0 | Al día |

- "Cobrado" = `order.payments.sum(:amount)`
- "Pendiente" = `order.outstanding_balance`
- "Estado" badge: green "Al día" when outstanding = 0, amber "Pendiente" when > 0
- Entire row wraps in a link to `web_order_path(order)`

### `orders/show`

Fix two broken `"#"` links:

1. Line ~49: customer name in the main info card  
   `link_to @order.customer.name, "#"` → `link_to @order.customer.name, web_customer_path(@order.customer)`

2. Line ~267: customer name in the right sidebar  
   `link_to @order.customer.name, "#"` → `link_to @order.customer.name, web_customer_path(@order.customer)`

For credit orders, add a "Pagos de esta venta" section in the right sidebar (below "Info del Cliente"), showing:
- Each payment linked via `order_id`: date, amount, method
- Total cobrado + saldo pendiente (`order.outstanding_balance`)
- If no linked payments: "Sin cobros registrados para esta venta"

This section is only shown when `@order.credit_order_type?`.

### `customers/debtors` (new view)

**Route:** `GET /web/customers/debtors`

**Layout:** consistent with `customers/index` — full-width table card.

**Columns:**

| Nombre | Tipo | Saldo | Último Pago | Días sin pagar | Acciones |
|---|---|---|---|---|---|
| Auto Service La Plata | Taller | $3.061.161 | 2026-05-04 | 2 | Ver / Registrar Pago |

- Sorted by saldo descendente (highest debt first)
- "Días sin pagar": if no payments ever → "Sin pagos"; else `Date.today - last_payment_date`
- "Días sin pagar" > 30 → shown in red; 15–30 → amber; < 15 → normal
- Empty state: illustration + "Todos los clientes están al día"
- Each row: "Ver" → `web_customer_path`, "Registrar Pago" → `new_web_customer_payment_path` (only shown with policy check)

### Dashboard

The existing receivables metric total links to `debtors_web_customers_path`. No change to the metric calculation itself.

---

## Testing

### `spec/models/order_spec.rb`

```
#outstanding_balance
  - returns 0 for immediate orders
  - returns total_amount when no payments exist
  - returns difference after partial payment
  - returns 0 when fully paid
```

### `spec/models/payment_spec.rb`

Fix existing test `"is invalid when amount exceeds order total"` to match new error message.

Add:
```
amount_within_order_total (with existing partial payment)
  - is valid when amount covers the remaining balance exactly
  - is invalid when amount exceeds the remaining balance
  - is valid when order is nil (standalone payment)
```

### `spec/requests/web/customers_spec.rb`

```
GET /web/customers/debtors
  - returns 200 for authorized user
  - includes customers with balance > 0
  - excludes customers with balance = 0
  - excludes customers without credit account
  - is sorted by balance descending
```

---

## Known limitation: unallocated payments

`Order#outstanding_balance` sums only payments with `order_id` pointing to that specific order. Standalone payments (`order_id: nil`, registered via "Registrar Pago") reduce `Customer#current_balance` but do NOT reduce any individual order's outstanding balance.

This means a customer can have `current_balance = 0` while some orders still show `outstanding_balance > 0`. This is expected behavior under the current unallocated payments model.

To make this clear in the UI:
- `customers/show` order table shows both columns but includes a footnote: "El saldo pendiente por venta solo refleja cobros vinculados directamente a esa venta. Los abonos a cuenta se descuentan del saldo total del cliente."
- The right sidebar balance ("Saldo: $0") remains the authoritative figure

Full payment allocation (linking standalone payments to specific orders) is deferred to a future feature.

---

## Data / performance notes

- `Customer#current_balance` makes 2 SQL queries per call. With < 20 customers in the index and < 10 debtors, total queries are acceptable without caching.
- If the list grows past ~50 rows, add `current_balance` as a database-backed column updated by callbacks (same pattern as `current_stock`). This is not needed now.
- `Customer.with_outstanding_balance` uses correlated subqueries — verified safe for PostgreSQL with small datasets.

---

## Files to modify / create

**Modify:**
- `app/models/order.rb` — add `outstanding_balance`
- `app/models/payment.rb` — fix `amount_within_order_total`
- `app/models/customer.rb` — add `with_outstanding_balance` scope
- `app/policies/customer_policy.rb` — add `debtors?`
- `app/controllers/web/customers_controller.rb` — add `debtors` action
- `config/routes.rb` — add `collection { get :debtors }`
- `app/views/layouts/web/_sidebar.html.haml` — extend Ventas group, Clientes group
- `app/views/web/customers/index.html.haml` — add saldo column
- `app/views/web/customers/show.html.haml` — clickable orders, cobrado/pendiente cols
- `app/views/web/orders/show.html.haml` — fix broken customer links
- `app/views/web/dashboard/index.html.haml` — link receivables metric
- `spec/models/order_spec.rb` — new examples
- `spec/models/payment_spec.rb` — fix + new examples
- `spec/requests/web/customers_spec.rb` — new or extend

**Create:**
- `app/views/web/customers/debtors.html.haml`

**Update:**
- `WORKING_CONTEXT.md` — reflect new debtors page and outstanding_balance
