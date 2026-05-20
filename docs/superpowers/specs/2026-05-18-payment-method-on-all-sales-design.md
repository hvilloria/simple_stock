# Payment Method on All Sales — Design Spec

**Date:** 2026-05-18
**Feature:** feat_07-payment-method-on-all-sales

## Context

Today the system records payment method only for credit orders (via `Payment` + `PaymentAllocation`). Immediate sales show a payment method selector in the form but discard it — no `Payment` record is created. This makes it impossible to know how a customer paid for a cash sale, which blocks:

- Daily cash reconciliation (cierre de caja)
- Per-sale payment detail (how was order #X paid?)
- Sales goal tracking by payment method

The core insight: the difference between immediate and credit sales is not *what happens* but *when*. Immediate sales are paid in full at the moment of sale; credit sales are paid in parts over time. In both cases, money is received and its method should be recorded.

---

## Scope

### In scope

1. Remove `customer_must_have_credit_account` validation from `Payment` — payments now represent money received regardless of customer type
2. Fix `Customer#current_balance` to use allocation-based formula — only payments linked to credit orders affect the credit balance
3. Extend `Sales::CreateOrder` to accept multiple payment entries (`payments:` array) for both immediate and credit orders
4. For immediate orders: payments are **required**, sum must equal `total_amount`
5. For credit orders: payments are **optional** (partial or zero upfront), sum must be `<= total_amount`
6. Update `Web::OrdersController#create` and `parse_initial_payment` to send the new `payments:` array
7. Update `new.html.haml` — replace the single `creditPaymentSection` with a multi-row payment block inside Card 1 (Información del Cliente), visible for all order types
8. Update `order-form` Stimulus controller to handle dynamic add/remove rows and per-type validation
9. Update specs: `Payment`, `Order`, `Sales::CreateOrder`, `Web::OrdersController`

### Out of scope

- Daily cash register UI (cierre de caja) — separate feature, will query `Payment` + `PaymentAllocation`
- Refund tracking when immediate orders are cancelled
- Post-sale payment adjustment for immediate orders (they are always fully paid at creation)
- Changing `Sales::CancelOrder` behavior for payment cleanup

---

## Architecture

### No schema migrations required

All changes are behavioral. The `payments` and `payment_allocations` tables already have the right shape.

---

## Backend changes

### 1. `Payment` model — remove credit account validation

**Remove** the `customer_must_have_credit_account` validation entirely.

`Payment` represents a tender: money physically received. This is valid for any customer, including `Cliente Mostrador` (retail, no credit account). The credit account constraint was only needed when payments were exclusively used for credit balance management — that constraint now lives in `Customer#current_balance` via the allocation formula instead.

```ruby
# REMOVE this validation:
validate :customer_must_have_credit_account
```

### 2. `Customer#current_balance` and `Customer.with_outstanding_balance` — allocation-based formula

**Current (buggy for the new design):**
```ruby
def current_balance
  return 0 unless has_credit_account?
  total_credit_sales = orders.credit.confirmed.sum(:total_amount)
  total_payments     = payments.sum(:amount)   # ← sums ALL payments, including immediate-sale payments
  total_credit_sales - total_payments
end
```

**Fixed:**
```ruby
def current_balance
  return 0 unless has_credit_account?
  credit_owed = orders.credit.confirmed.sum(:total_amount)
  credit_paid = PaymentAllocation
                  .joins(:order)
                  .where(orders: { customer_id: id, order_type: "credit", status: "confirmed" })
                  .sum(:amount)
  credit_owed - credit_paid
end
```

This means:
- Immediate-sale payments for a credit customer → NOT counted in credit balance (they're linked to immediate orders)
- Credit-order payments → counted in credit balance (linked to credit orders)

**`Customer.with_outstanding_balance`** — must also be updated to match. Its current formula sums ALL payments for the customer in the correlated subquery. With the new design, immediate-sale payments would incorrectly offset the credit check, potentially hiding real debtors (e.g., a customer owes $100 credit but made a $200 cash purchase — the scope would incorrectly show them as "al día").

Updated scope:

```ruby
scope :with_outstanding_balance, -> {
  with_credit_account.where(
    "( SELECT COALESCE(SUM(o.total_amount), 0)
       FROM orders o
       WHERE o.customer_id = customers.id
         AND o.order_type = 'credit'
         AND o.status = 'confirmed' )
     >
     ( SELECT COALESCE(SUM(pa.amount), 0)
       FROM payment_allocations pa
       JOIN orders o ON pa.order_id = o.id
       WHERE o.customer_id = customers.id
         AND o.order_type = 'credit'
         AND o.status = 'confirmed' )"
  )
}
```

This scope and `current_balance` now use the same accounting logic — both reflect only credit-order-linked payments.

### 3. `Sales::CreateOrder` — `payments:` array replaces `initial_payment:`

The `initial_payment:` parameter is replaced by `payments:` (plural), an array of `{ amount:, payment_method: }` hashes.

```ruby
def self.call(customer:, items:, order_type:, channel: nil, source: "live",
              sale_date: nil, paper_number: nil, payments: [])
```

**Validation rules:**

For `immediate` orders:
- `payments` must be present and non-empty
- Each entry: `amount > 0`, `payment_method` in `Payment::PAYMENT_METHODS`
- `payments.sum(:amount)` must equal `total_amount` (within float rounding tolerance)

For `credit` orders:
- `payments` is optional (empty array = no upfront payment)
- Each entry: `amount > 0`, `payment_method` in `Payment::PAYMENT_METHODS`
- `payments.sum(:amount)` must be `<= total_amount`

**`create_payments` method** (replaces `create_initial_payment`):

```ruby
def create_payments
  @payments_data.each do |entry|
    payment = Payment.create!(
      customer:       @customer,
      amount:         entry[:amount],
      payment_method: entry[:payment_method],
      payment_date:   @sale_date
    )
    PaymentAllocation.create!(
      payment: payment,
      order:   @order,
      amount:  entry[:amount]
    )
  end
end
```

Called unconditionally after `create_order_items` when `@payments_data` is non-empty.

### 4. `Web::OrdersController` — update `parse_initial_payment` → `parse_payments`

```ruby
def parse_payments
  entries = params[:payments]
  return [] if entries.blank?

  entries.values.filter_map do |entry|
    amount = entry[:amount].to_f
    next if amount <= 0

    {
      amount:         amount,
      payment_method: entry[:payment_method].presence || "cash"
    }
  end
end
```

Params shape from the form (indexed hash, Rails convention):
```
payments[0][amount]=80000&payments[0][payment_method]=cash
payments[1][amount]=20000&payments[1][payment_method]=transfer
```

The controller calls `Sales::CreateOrder` with `payments: parse_payments`.

---

## UI changes

### `new.html.haml` — replace `creditPaymentSection`

**Remove** lines 80–97 (the existing `creditPaymentSection` div with single amount + single method inputs).

**Replace with** a multi-row payment block that:
- Lives in the same position inside Card 1 (below the customer selector, above Canal de Venta)
- Is always rendered in the HTML (no `hidden` class on the outer container)
- Shows "Detalle de Pago" + required badge for immediate orders
- Shows "Cobro al Momento" + optional badge for credit orders
- Supports dynamic add/remove rows via Stimulus
- Renders one initial row by default

```haml
-# Sección de pago (visible para todos los tipos de venta)
.border-t.border-gray-200.pt-4{ data: { order_form_target: "paymentSection" } }
  .flex.items-center.justify-between.mb-3
    %div
      %h4.text-sm.font-semibold.text-gray-900{ data: { order_form_target: "paymentSectionTitle" } }
        Detalle de Pago
      %p.text-xs.text-gray-500.mt-0.5{ data: { order_form_target: "paymentSectionSubtitle" } }
        La suma debe coincidir con el total de la venta
    %span.text-xs.font-semibold.px-2.py-0.5.rounded{ data: { order_form_target: "paymentSectionBadge" } }
      Requerido

  -# Contenedor de filas de pago (dinámico)
  %div{ data: { order_form_target: "paymentRows" }, class: "space-y-2 mb-3" }
    -# Primera fila (siempre presente)
    .flex.gap-2.items-center{ data: { order_form_target: "paymentRow" } }
      = select_tag "payments[0][payment_method]",
          options_for_select([["💵 Efectivo", "cash"], ["🏦 Transferencia", "transfer"],
                              ["📄 Cheque", "check"], ["💳 Tarjeta", "card"]], "cash"),
          class: "flex-1 px-3 py-2 border border-gray-300 rounded-lg text-sm ..."
      = number_field_tag "payments[0][amount]", nil,
          step: "0.01", min: "0", placeholder: "Monto",
          data: { action: "input->order-form#updatePaymentTotal" },
          class: "w-32 px-3 py-2 border border-gray-300 rounded-lg text-sm ..."
      %button{ type: "button", data: { action: "click->order-form#removePaymentRow" },
               class: "text-gray-400 hover:text-red-500 text-lg px-1" } ×

  %button{ type: "button", data: { action: "click->order-form#addPaymentRow" },
           class: "text-xs text-slate-600 hover:text-slate-900 font-medium flex items-center gap-1 mb-3" }
    %span.text-base +
    Agregar método de pago

  -# Resumen de pago
  .rounded-lg.p-3.text-sm{ data: { order_form_target: "paymentSummary" } }
    .flex.justify-between.mb-1
      %span.text-gray-600 Total declarado
      %span.font-semibold{ data: { order_form_target: "paymentDeclared" } } $0
    %p.font-semibold.text-xs.mt-1{ data: { order_form_target: "paymentStatus" } }
```

### `order-form` Stimulus controller — key changes

New targets: `paymentSection`, `paymentSectionTitle`, `paymentSectionSubtitle`, `paymentSectionBadge`, `paymentRows`, `paymentRow`, `paymentDeclared`, `paymentStatus`, `paymentSummary`

**`updateOrderType()`** — when order type radio changes:
- Immediate: set title "Detalle de Pago", subtitle "La suma debe coincidir con el total", badge "Requerido" (red)
- Credit: set title "Cobro al Momento", subtitle "Opcional — si el cliente paga algo ahora", badge "Opcional" (gray)
- Call `updatePaymentTotal()`

**`updatePaymentTotal()`** — on any payment input change:
- Sum all `input[name*="amount"]` inside `paymentRows`
- Update `paymentDeclared`
- For immediate: compare sum to order total → green (ok) / red (mismatch) on `paymentSummary`; enable/disable submit
- For credit: always green if sum <= total; show pending balance

**`addPaymentRow()`** — clone the first row template, update name indexes, append to `paymentRows`

**`removePaymentRow(event)`** — remove the closest `paymentRow` if more than 1 row exists

**Submit guard** — `updateSubmitButton()` for immediate orders: disabled unless `paymentSum ≈ orderTotal` AND products are present

---

## Testing

### `spec/models/payment_spec.rb`

- Remove test: `"is invalid when customer has no credit account"` — validation no longer exists
- Add: `"is valid for a retail customer without credit account"` (mostrador scenario)
- Add: `"is valid when customer is nil"` — verify no crash

### `spec/models/customer_spec.rb`

- Add `#current_balance` examples:
  - Returns 0 for non-credit customers (unchanged)
  - Only counts payments allocated to credit orders
  - Immediate-sale payments for a credit customer do NOT reduce their credit balance
  - Fully paid credit order shows balance 0

- Add `.with_outstanding_balance` examples:
  - Excludes customer whose only payments are for immediate orders
  - Includes customer with unpaid credit orders even if they have immediate-sale payments

### `spec/services/sales/create_order_spec.rb`

- Replace all `initial_payment:` usages with `payments:` array
- Add: immediate order with `payments: []` → fails validation
- Add: immediate order with payments not summing to total → fails validation
- Add: immediate order with split payments → creates 2 Payments + 2 Allocations
- Add: credit order with `payments: []` → succeeds (no Payments created)
- Add: credit order with partial upfront payment → creates 1 Payment + 1 Allocation

### `spec/requests/web/orders_spec.rb`

- Update `POST /web/orders` examples to use `payments[0][amount]` / `payments[0][payment_method]` param shape
- Add: immediate order without payments → redirects back with error
- Add: immediate order with valid split payments → creates order + 2 Payments

---

## Key invariants preserved

- `Order#outstanding_balance` — unchanged. Returns 0 for immediate (correct: always fully paid). Returns `total - allocations.sum` for credit.
- `Customer.with_outstanding_balance` — scope uses correlated subqueries comparing order totals to payments by customer. Verify it still returns correct results after `current_balance` formula change.
- `Sales::CancelOrder` — unchanged. Destroys `PaymentAllocation`s; `Payment`s remain (existing known limitation applies to both immediate and credit).
- `Payments::AllocatePayment` — unchanged. Remains exclusive to credit orders for post-sale payments.

---

## Files to modify

- `app/models/payment.rb` — remove `customer_must_have_credit_account`
- `app/models/customer.rb` — fix `current_balance` formula and `with_outstanding_balance` scope
- `app/services/sales/create_order.rb` — `payments:` array, `create_payments` method
- `app/controllers/web/orders_controller.rb` — `parse_payments` replaces `parse_initial_payment`
- `app/views/web/orders/new.html.haml` — replace payment section
- `app/javascript/controllers/order_form_controller.js` — extend for multi-row payments
- `spec/models/payment_spec.rb`
- `spec/models/customer_spec.rb`
- `spec/services/sales/create_order_spec.rb`
- `spec/requests/web/orders_spec.rb`
- `WORKING_CONTEXT.md` — update payment flow description

## Files to create

None.
