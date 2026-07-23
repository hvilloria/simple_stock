# Swap products on payments on account (feat_22)

**Date:** 2026-07-22
**Branch:** `feat_22-edit-products-not-paid-on-payments-on-account`

## Goal

Sellers sometimes need to exchange a product noted on a payment-on-account
order for a completely different one (e.g. imported part swapped for the local
version). Today nothing can be changed after the order is created. This feature
lets vendedor/admin replace the product (and its unit price) on any line that
has **not** been marked as delivered, recalculating the order total.

## Decisions

1. **Scope of the edit:** replace the line's `product` and/or adjust its
   `quantity`. No adding or removing lines. There is **no price field**: when
   the product changes, the line takes the new product's catalog
   `price_unit`; when only the quantity changes, the line **keeps its
   original `unit_price`** (the catalog is not re-read, so a quantity tweak
   never silently moves the price).
2. **Constraint:** delivered lines (`delivered_at` present) are never editable.
   The service re-checks this at save time (guards against a concurrent
   delivery mark).
3. **Roles:** vendedor + admin (same criterion as marking deliveries). Caja
   sees no edit affordance.
4. **No overpayment guard (known gap, user decision):** if a swap to a cheaper
   product leaves the new total below what was already collected, the edit is
   still allowed. The balance shows negative and
   `refresh_status_from_balance!` confirms the order. Accepted as technical
   debt; `WORKING_CONTEXT.md` gets a known-gap note.
5. **Total recalculation is delta-based, never a re-sum.**
   `Order#calculate_total!` would wipe the effective discounts that
   `Payments::CollectOnAccount#apply_discount!` already subtracted from
   `total_amount`. Instead:
   `delta = (new_quantity × new_price) − (old_quantity × old_price)` applied
   to **both** `total_amount` and `original_total_amount`. This keeps the
   `original_total_amount ≥ total_amount` model invariant (the gap between
   them — accumulated effective discounts — is unchanged).
6. **Price comes from the catalog, not the form.** No price input and no
   write-back (nothing is typed, so there is nothing to write back — this
   flow intentionally differs from `Sales::CreateOrder`'s manual pricing).
   Guard: if the chosen product's `price_unit` is not > 0, the swap is
   rejected ("El producto no tiene precio de catálogo — cargalo en
   Productos"), since there is no way to type one here.
7. **Status refresh:** the service calls `refresh_status_from_balance!` at the
   end. It is bidirectional: swapping to a pricier product on a fully-paid
   (confirmed, undelivered) order reopens it to `pending` — intended.
8. **UI direction:** dedicated edit page per line (approach A), reached from a
   new row-actions column on the show view (wireframe variant A). Full-page
   form → service → redirect, like the rest of the app.

## UI changes

### 1. `web/payments_on_account/:id` (show) — row actions column

The products table gains a last, header-less column:

```
Producto                   Subtotal      Entrega              [acciones]
─────────────────────────────────────────────────────────────────────────
Amortiguador delantero     $200.000,00   ✓ entregado          —
Kit de embrague            $200.000,00   ☐ marcar entregado   [⇄ Cambiar]
Bomba de agua importada    $100.000,00   ☐ marcar entregado   [⇄ Cambiar]
```

- `⇄ Cambiar` — ghost button (border only, quieter than "Guardar entrega"),
  links to the item edit page. Rendered only when the policy allows
  (`@can_edit_items`, vendedor+admin) **and** the line is undelivered.
- The actions column shows an em-dash whenever the row has no available
  action: delivered rows (any role) and every row when the viewer lacks
  `edit_item?` (caja). The Entrega column itself is unchanged for all roles.
- Everything else on the page is untouched (delivery form, payments history,
  summary, Cobrar).
- Flash messages from the edit flow render in the standard flash area.

### 2. `web/payments_on_account/:id/items/:item_id/edit` (new page)

Layout (eyebrow: talonario + contact; H1 "Cambiar producto"; back link
"← Volver a la operación"), one card:

- **Producto** (single section):
  - Product search box — reuses the `product-search` Stimulus component and
    `search_web_products_path` endpoint (same as `orders/new`). Empty
    dropdown state: "Sin resultados".
  - On page load the **current** product appears pre-selected (pill
    "actual") with the line's current price, so the form also serves a
    quantity-only change. Picking a search result replaces the selection and
    shows `Seleccionado: <name> · SKU <sku> · Precio catálogo: $X` (+ hidden
    `product_id`). The price is display-only — never an input.
  - **Cantidad**: numeric input, prefilled with the line's quantity, min 1.
  - Live preview (Stimulus): `Subtotal old → new`, `Total de la operación
    old → new`, `Saldo old → new`. Current totals passed via data
    attributes. A negative resulting balance is displayed as-is (decision 4).
- Buttons: `Cancelar` (link back to show) · `Guardar cambio` (submit,
  disabled until something changed — different product and/or different
  quantity — and quantity ≥ 1).
- Backend errors (item already delivered, product without catalog price,
  invalid quantity) redirect back to the edit page with an alert flash; the
  form re-starts from the persisted line (selection is not preserved —
  acceptable for this rare path).

## Backend

### Routes

```ruby
resources :payments_on_account, only: [ :index, :show ] do
  resource :payment, ...            # existing
  resources :items, only: [ :edit, :update ],
                    controller: "payments_on_account/items"
  member { post :deliver }          # existing
end
```

### Controller — `Web::PaymentsOnAccount::ItemsController`

Thin, mirrors `Web::PaymentsOnAccount::PaymentsController`:

- `edit`: load order (`Order.on_account.find`), load item from
  `@order.order_items`, `authorize @order, :edit_item?, policy_class:
  PaymentOnAccountPolicy`. Redirect with alert if the item is already
  delivered.
- `update`: same loading/authorization, then
  `Sales::ReplaceOrderItem.call(order_item:, product_id:, quantity:)`;
  on success redirect to show with notice "Producto actualizado", on failure
  redirect back to edit with `result.errors` alert.
- Params are plain values (`product_id`, integer `quantity`) — no currency
  parsing anywhere in this flow.

### Policy — `PaymentOnAccountPolicy#edit_item?`

```ruby
def edit_item?
  (user.vendedor? || user.admin?) && record.on_account_order_type? &&
    !record.cancelled_status?
end
```

The show view exposes it as `@can_edit_items` alongside `@can_deliver` /
`@can_collect`.

### Service — `Sales::ReplaceOrderItem`

`.call(order_item:, product_id:, quantity:)` → `Result`.

Validations (ValidationError → failure Result, same style as
`Payments::CollectOnAccount`):

- order is `on_account` and not cancelled
- `order_item.delivered_at` is nil ("El producto ya fue entregado")
- new product exists (`Product.active` — excludes soft-deleted and inactive)
- `quantity` is a positive integer
- when the product changes: new product's `price_unit > 0` ("El producto no
  tiene precio de catálogo — cargalo en Productos")

Price resolution:

- product changed → `new_price = new_product.price_unit`
- product unchanged → `new_price = order_item.unit_price` (line keeps its
  original price; quantity-only edit)

Transaction:

1. `delta = (new_quantity × new_price) − (old_quantity × old_price)` —
   computed on decimals.
2. `order_item.update!(product_id:, quantity:, unit_price: new_price)`
3. `order.update!(total_amount: total_amount + delta,
   original_total_amount: original_total_amount + delta)`
4. `order.refresh_status_from_balance!`

Notes:

- No `StockMovement` involved — delivery marks don't move stock today, so a
  swap has no inventory side effects (consistent with `Inventory::MarkDelivered`).
- No price write-back to the catalog (nothing is typed in this flow).
- A no-op submit (same product, same quantity) is accepted and simply
  redirects — the UI already keeps the button disabled in that case.

## Element mapping (audit result)

| Element | Status | Backing |
|---|---|---|
| Product search + JSON payload (`id, sku, name, price_unit`) | exists | `product_search_controller`, `Web::ProductsController#search` |
| Search authorization for vendedor | exists | `ProductPolicy#search?` |
| Soft-deleted/inactive products excluded from search | exists | `Product.active` + `acts_as_paranoid` |
| Row actions column + edit affordance | new | show view edit |
| `PaymentOnAccountPolicy#edit_item?` | new | one method |
| Nested routes + `ItemsController` | new | mirrors `payments` nesting |
| `Sales::ReplaceOrderItem` | new | service, Result pattern |
| Edit page view + glue Stimulus (selection, quantity, preview, submit gating) | new | pattern from `order_form_controller` |
| WORKING_CONTEXT.md known-gap note | new | docs |

No conflicts with: stock mutation rule (no stock touched), Result pattern,
thin controllers, Pundit, HAML-only.

## Edge cases

- **Concurrent delivery:** another user marks the line delivered while the
  edit page is open → service rejects, alert on redirect.
- **Order leaves the open list mid-edit** (settled/cancelled): service
  rejects via order-state validation.
- **Swap below collected amount:** allowed; negative balance displayed;
  order auto-confirms at balance ≤ 0 (known gap, decision 4).
- **Swap to pricier product on confirmed order:** balance reopens, status
  back to `pending`, order reappears in the open list (correct — it owes
  money again).

## Testing

- **Service spec** (`spec/services/sales/replace_order_item_spec.rb`):
  happy path (product swapped at catalog price, delta applied to both
  totals, status refresh), quantity-only edit keeps the original line price,
  delivered-item rejection, non-on_account rejection, cancelled rejection,
  quantity ≤ 0 rejection, unknown/soft-deleted product rejection, product
  without catalog price rejection, delta math with a prior discounted
  collection (original−total gap preserved), pricier swap demotes
  confirmed → pending.
- **Policy spec**: `edit_item?` per role.
- **Request specs** (`Web::PaymentsOnAccount::ItemsController`): authorization
  per role, edit of delivered item redirects with alert, successful update
  redirects to show, failed update redirects to edit with alert.
- **View/request check**: "Cambiar" affordance visible for vendedor/admin on
  undelivered rows only.

## Out of scope

- Adding or removing lines; editing the unit price directly (price always
  comes from the catalog when swapping).
- Overpayment guard / customer credit representation (known gap).
- Stock movements on delivery or swap (pre-existing TRACK_STOCK debt).
- Turbo-frame inline editing (can evolve later from this same route/service).
