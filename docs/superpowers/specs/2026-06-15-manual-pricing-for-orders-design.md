# Manual pricing for orders — design

Date: 2026-06-15
Branch: `feat_12-manual-pricing-for-orders`

## Context

The business is in an intermediate state regarding stock: inventory is being
taken but the platform must keep operating. Products are often bought the same
day they are sold (the vendor buys the part and calls the customer to pick it
up), so the catalog price (`product.price_unit`) is frequently stale, missing,
or simply not what the vendor agreed with the customer.

Selling products that are not yet entered as merchandise already works: the
sales UI submits `source: from_paper`, which skips stock validation, so a
product with `current_stock = 0` can be sold as long as it exists in the
catalog. This feature does **not** touch that.

The actual need: let the vendor type the unit price manually when creating the
sale note, and use that price both for the order and as the product's updated
catalog price for future sales.

Note on `source`: in practice there is a single sales path today — every note
is created with a `paper_number`, so `live` and `from_paper` are functionally
equivalent. The price rules below therefore apply to all `source` values with
no special-casing by mode.

## What already exists

- `Sales::CreateOrder` already accepts a per-item `unit_price` and uses
  `item.unit_price || product.price_unit || 0`.
- The form already submits a hidden `purchase_items[][unit_price]` field.

What is missing is (a) making the price editable in the UI, and (b) writing the
entered price back to the product.

## Design

### 1. Frontend — `order_form_controller.js` + `web/orders/new.html.haml`

The unit price stops being read-only text and becomes an editable
`<input type="number">`, mirroring the existing quantity pattern (visible input
+ synced hidden `purchase_items[][unit_price]`).

- The input is prefilled with `item.price_unit` (already populated from the
  product when the item is added).
- A new `updatePrice(event)` handler updates `this.items[index].price_unit`,
  recalculates the line subtotal and the summary totals. This is **purely
  client-side** — it never calls the backend. The price persists only on form
  submit, when the order is created.
- `updateSubmitButton` gains one condition: the submit button stays disabled if
  **any** item has a price `<= 0`, in addition to the existing conditions
  (items present + customer + paper_number).

### 2. Backend — `Sales::CreateOrder`

- **New validation:** every item must have `unit_price > 0`. This hardens the
  service, which today tolerates `nil` (treated as 0). It applies to all
  `source` values. This is an intentional behavior change: the `nil`-price
  tolerance built for transcribing old paper notes is no longer reachable from
  the UI, since the single live path always supplies a price. Existing specs
  that pass `nil`/missing `unit_price` will be updated.
- **Write-back:** within the same transaction, when each `OrderItem` is created,
  the product's `price_unit` is updated with the entered price
  (`product.update!(price_unit: final_price)`). Because the validation
  guarantees `> 0`, the catalog is never clobbered with 0. `price_unit` is not a
  protected field like stock or weighted-average cost, so a direct update is the
  correct mechanism.

### 3. "Not editable after creation" — no work required

There is no order edit action and the order `show` view is read-only, so the
price is frozen once the note is created. Nothing to add.

## Business rules check

- **Stock:** untouched. No `StockMovement`, no `current_stock` mutation.
- **`price_unit`:** has no immutability rule (unlike `current_stock` and
  `cost_unit`), so writing it directly is legitimate.
- **Variants:** price is per-variant (each `Product` is a variant), and the form
  deduplicates lines by `product_id`, so there is no write conflict.
- **New side effect:** creating an order now also updates the catalog price of
  each product sold. This is the intended behavior.

## Testing

- `Sales::CreateOrder` spec: write-back updates `product.price_unit`; rejects
  items with `unit_price <= 0`.
- Update existing specs that relied on `nil`/missing `unit_price`.
- Request spec for the orders create flow with manual prices (optional, if it
  adds meaningful coverage).

## Out of scope

- Creating products on the fly from the order form (products must already exist
  in the catalog).
- Any change to stock validation or `source` semantics (tracked separately in
  `docs/pendientes.txt` item 16).
