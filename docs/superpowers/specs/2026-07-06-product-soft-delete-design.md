# Product soft-delete (admin-only) — Design

**Pendiente #1:** "feature -> add delete button with confirmation only for admins"

Date: 2026-07-06

## Goal

Give admins a one-click **Delete** button (with confirmation) on the product
screen. "Delete" is a **soft delete** implemented with the `paranoia` gem
(`deleted_at` timestamp), **not** a reuse of the existing `active` boolean.

## Why not the `active` flag

Setting `active: false` leaves a real, live row. That row still participates in
the variant-uniqueness validation (`sku + product_type + origin + brand`), so
later editing another variant to add info can collide with an "archived" product
and be blocked or cause confusion. A dedicated `deleted_at` soft-delete, with the
uniqueness check scoped to `deleted_at IS NULL`, removes deleted rows from
uniqueness while keeping them for foreign-key integrity and history. `active`
remains a separate, orthogonal concept (discontinued-but-present).

## Foreign-key reality (why not a hard delete)

`order_items`, `invoice_items`, and `credit_note_items` all have
`product_id NOT NULL` with FK constraints and no cascade. A real `product.destroy`
would raise a foreign-key violation for any product that was ever sold, invoiced,
or credit-noted. Soft delete keeps the row, so all history stays valid.

## Changes

### 1. Gem
Add `gem "paranoia", "~> 3.0"` to the Gemfile; `bundle install`.

### 2. Migration
- `add_column :products, :deleted_at, :datetime`
- `add_index :products, :deleted_at`

### 3. `Product` model
- Add `acts_as_paranoid` (default scope `deleted_at IS NULL`; overrides `destroy`
  to set `deleted_at`; provides `restore`, `with_deleted`, `only_deleted`).
- **Uniqueness fix (core of the feature):** change the sku uniqueness validation
  to ignore soft-deleted rows:
  ```ruby
  validates :sku, uniqueness: { scope: [:product_type, :origin, :brand],
                                conditions: -> { where(deleted_at: nil) } },
                  if: -> { origin.present? }
  ```
  **This is not enough on its own.** The DB unique index
  `index_products_on_variant_uniqueness` (`[sku, product_type, brand, origin]`)
  is a plain unique index, so `save!` of a live variant reusing a soft-deleted
  variant's identity still raises `ActiveRecord::RecordNotUnique` at the DB layer
  even when the model validation passes. A migration must convert it to a
  **partial** unique index `WHERE deleted_at IS NULL` (preserving the existing
  composite identity + NULLS-DISTINCT behavior, additionally excluding
  soft-deleted rows). The spec test must assert real persistence (`save!`), not
  just `be_valid`.
- **Preserve the stock ledger:** remove `dependent: :destroy` from
  `has_many :stock_movements`. Paranoia would otherwise cascade a hard delete of
  the movements (StockMovement is not paranoid) on soft-delete, destroying audit
  history. The product row survives, so the FK on `stock_movements` stays valid.

### 4. Historical associations opt back in
Paranoia's default scope hides soft-deleted products, so `item.product` would
return `nil` and crash the many views that dereference it without safe navigation
(e.g. `orders/show.html.haml:141` `item.product.sku`) and `Sales::CancelOrder`
(reads `item.product` to build the restock movement). Add `-> { with_deleted }`:
- `OrderItem`   → `belongs_to :product, -> { with_deleted }`
- `InvoiceItem` → `belongs_to :product, -> { with_deleted }`
- `CreditNoteItem` → `belongs_to :product, -> { with_deleted }`
- `StockMovement` → `belongs_to :product, -> { with_deleted }`

### 5. Route
Add `:destroy` to `resources :products`.

### 6. Controller — `Web::ProductsController#destroy`
- `@product = Product.find(params[:id])`
- `authorize @product` — reuses the existing `ProductPolicy#destroy?` (already
  `user.admin?`); no policy change.
- `@product.destroy` (now soft).
- Redirect to `web_products_path` with a Spanish notice
  (e.g. `"Producto eliminado exitosamente"`).

### 7. View — `app/views/web/products/show.html.haml`
In the header action area (next to "Editar Producto"), admin-only:
```haml
- if policy(@product).destroy?
  = button_to web_product_path(@product), method: :delete,
              data: { turbo_confirm: "¿Eliminar este producto? Dejará de aparecer en el sistema." },
              class: "btn-danger" do
    %span Eliminar
```
Matches the existing `button_to` + `turbo_confirm` + `btn-danger` pattern used by
Suppliers (`suppliers/show.html.haml:16`) and Orders.

### 8. Restore
**No restore UI in this iteration** (scope kept to the delete button). Deleted
products are recoverable via console (`Product.only_deleted`, `record.restore`).
A "Papelera"/restore view can be added later if needed.

## Out of scope (explicit non-goals)
- No hard `.destroy` / `really_destroy!` from the UI.
- No delete button on the index rows (show page only).
- No new policy methods; no restore route/action/view.
- No changes to other resources (customers, orders, invoices, suppliers).
- `active` boolean behavior is untouched.

## Tests (`spec/`)
- **Request** (`spec/requests/web/products_spec.rb` or equivalent):
  - admin `DELETE /web/products/:id` → row persists, `deleted_at` set, product
    absent from default scope, redirect + notice.
  - vendedor and caja → forbidden (redirect with flash, not soft-deleted).
- **Regression:** a product referenced by an order, once soft-deleted, still
  renders on the order show page (`with_deleted`) and `Sales::CancelOrder` still
  restocks without a nil error.
- **Model:** uniqueness validation allows a new/edited live variant whose
  `sku + product_type + origin + brand` matches a soft-deleted product.
- **Policy** (if not already covered): `ProductPolicy#destroy?` true only for admin.
