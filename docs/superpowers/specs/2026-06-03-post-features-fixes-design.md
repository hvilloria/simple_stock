# Post-features fixes — design

Date: 2026-06-03
Branch base: `fix_04-several-fixes-related-to-credit-account-and-orders`

A batch of small, independent UI/behavior fixes accumulated after several
features. Each item below is self-contained. One commit for the whole batch
(per project convention: one commit per feature, no intermediate commits).

Out of scope this round: `docs/pendientes.txt` #5 (MP/Banco payment methods)
and #15 (global real-time amount formatting).

---

## 1. `web/products` index — replace "Estado" column with "Precio"

**Files:** `app/views/web/products/index.html.haml`, `app/models/product.rb`

- Replace the `ESTADO` header (currently lines ~82-83) with `PRECIO`, rendered
  via `sortable_column(:price_unit, "PRECIO", params)`.
- Replace the active/inactive badge cell (currently lines ~137-142) with the
  formatted price: `currency_ar(product.price_unit)`, falling back to `—` when
  `price_unit` is nil/blank.
- Add `price_unit` to the `allowed_columns` whitelist in
  `Product.sorted_by` (`product.rb` ~line 94) so the new column sorts safely.
- Column count stays 9 → empty-state `colspan: 9` unchanged.
- The status **filter** dropdown in the filters bar stays (still works
  server-side via `by_status`); only the table column changes.

## 2. Cart modal (products index) — show unit price per line + total

**Files:** `app/javascript/controllers/cart_controller.js`,
`app/views/web/products/index.html.haml`

- `price_unit` is already present in the product JSON serialized on the
  add-to-cart button (`only: [:id, :sku, :name, :brand, :current_stock,
  :price_unit]`). No backend change.
- In `renderPanel`, add a unit-price line to each cart row.
- Add a **Total** row to the modal footer. Introduce a `cartTotal` Stimulus
  target in the modal footer (`index.html.haml`) and update it from
  `renderPanel` / `updateCount`.
- Formatting: `Intl.NumberFormat('es-AR', { minimumFractionDigits: 2,
  maximumFractionDigits: 2 })` for unit prices and the total.

## 3. `web/orders/new` — allow selling without stock (paper mode by default)

**Why:** stock is not enforced today (no inventory system yet); the vendor is
trusted to know the product exists. The form currently sends no `source`, so
`Web::OrdersController#create` defaults to `"live"` and
`Sales::CreateOrder` validates stock. Fix by making the flow explicitly
`from_paper`, whose branch already skips stock validation and already requires
`paper_number` (which the form already mandates).

**Files:** `app/views/web/orders/new.html.haml`,
`app/javascript/controllers/product_search_controller.js`,
`app/javascript/controllers/order_form_controller.js`, `WORKING_CONTEXT.md`

- Add a hidden field `source` = `"from_paper"` to the order form.
- **No change to `Sales::CreateOrder`** — the live-validation code stays intact
  for future use; we simply stop routing through it.
- `product_search_controller.js#selectProduct`: remove the zero-stock
  `alert`/early-return so any product can be selected. Keep the "Sin stock"
  badge as informational only.
- `order_form_controller.js#updateQuantity`: drop the `<= max_stock` cap;
  remove the `max="${item.max_stock}"` attribute from the rendered quantity
  input so quantity isn't limited by stock.
- Update `WORKING_CONTEXT.md`: note that `web/orders/new` submits
  `source: from_paper` by default, so stock is not validated at sale time
  (vendor-trusted). Adjust the existing line that says live validation applies.

## 4. `web/orders/new` — summary always sticky on the right

**Files:** `app/views/web/orders/new.html.haml`

- Restructure the cards grid to mirror `products/_form.html.haml`:
  - `lg:grid-cols-3`.
  - Left column `col-span-2`: *Información del Cliente* + *Productos* stacked
    with `space-y-6`.
  - Right column `col-span-1`: *Resumen de Venta* with `lg:sticky lg:top-24`.
- Remove the `md:row-span-4` hack that let *Productos* push the summary below.

## 5. `web/customers/:id/payments/new` — "Cobrar" decimal formatting

**Why:** the amount input doesn't follow the app's AR decimal format. Match
the `products/new` price behavior by reusing the existing `currency-input` and
`product-form` Stimulus controllers.

**Files:** `app/views/web/customers/payments/new.html.haml`,
`app/javascript/controllers/payment_allocation_controller.js`

- Change the amount `number_field_tag` → `text_field_tag` with
  `data-controller="currency-input"` and actions
  `input->payment-allocation#recalc blur->currency-input#format
  focus->currency-input#unformat`. Keep `data-role="amount-input"` and the
  `disabled` default. Drop `step`/`min` (no longer a number field).
- Add `product-form` as a second controller on the form and
  `turbo:submit-start->product-form#handleSubmit` so all currency inputs are
  cleaned (`1.234,56` → `1234.56`) before submit. The controller parses
  `row[:amount].to_f`, so this keeps the backend correct.
- `payment_allocation_controller.js`:
  - Add a `parseAmount(str)` helper (strip `.`, replace `,` with `.`,
    `parseFloat`).
  - In `updateSummary`, read the amount via `parseAmount` instead of raw
    `parseFloat`.
  - In `recomputeCard` (auto-fill of `amountInput.value`), write an es-AR
    formatted string (2 decimals) instead of raw `toFixed(2)`.

## 6. `web/products/new` — remove "Categoría" field

**Files:** `app/views/web/products/_form.html.haml`

- Remove the category `f.select` block (currently lines ~111-116).
- **No model change:** `product.rb` validates only
  `inclusion: { in: CATEGORIES, allow_blank: true }` — no presence constraint,
  so nothing forces a category. The `CATEGORIES` constant, the index filter,
  and the index column stay for existing/imported data.

## 7. `web/products/new` — cost currency: default ARS, USD disabled

**Files:** `app/views/web/products/_form.html.haml`

- USD radio: add `disabled: true` and gray out its container.
- ARS radio: default checked via `checked: product.cost_currency != 'USD'`
  (so new products default to ARS).
- Editing an existing product whose `cost_currency` is `USD` (set automatically
  by `recalculate_average_cost!`) still shows USD checked-but-disabled —
  acceptable read-only display.

---

## Testing

- Manual verification of each view (`/run` or browser) is the primary check —
  these are UI/JS changes.
- Run `bundle exec rspec` and `bundle exec rubocop` to confirm no regressions
  in the touched Ruby (`product.rb`, views) — no service/model logic changes
  expected beyond the `allowed_columns` whitelist addition.
