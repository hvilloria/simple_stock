# Stock adjustment page — design

**Status:** approved in conversation 2026-09-30, pending written-spec review.
**Work item:** feat_34 (joins the stock reactivation branch; squashed with it).
**Wireframes:** https://claude.ai/artifact/LFzvmYbMTRhGoXeiCyDtMM (source: `.superpowers/mockups/ajuste-de-stock.html`, git-ignored).

## Intent

Until now stock moves only through invoices (goods in) and sale notes (goods out). An admin needs to correct the count in the shop without inventing an invoice or a sale: after a physical count, a breakage, a miscount. The admin types **how many units there are now**; the system works out the difference and records it as an adjustment with who did it, why, and when.

Success: after saving, each product's stock equals the number typed; the change shows in the product's "Movimientos de Stock Recientes" as an adjustment naming the admin and the reason; no role other than admin can see or use the page.

## Decisions

| # | Decision |
|---|---|
| A1 | One page, several products: search a product, add it to a table, type the counted number. Not one product at a time, not a bulk import. |
| A2 | The admin enters the **counted** number (≥ 0), never a delta. The difference is computed **at save time** against the sum of the product's movements in that instant (not the cached `current_stock`), under a row lock, so a sale in between does not change the result: the stock ends at the number typed. |
| A3 | Reuse the mechanism: `ProductPolicy#adjust_stock?` (already `user.admin?`) and `Inventory::AdjustStock`. Each changed line writes one `adjustment` movement. |
| A4 | Who did it: `stock_movements` gains a nullable `user_id`. Only this page fills it; sales and invoices leave it null (their origin already names the person). No header model — without a list of adjustments it would add nothing. |
| A5 | One reason per adjustment, required. It is stored as the `note` of every movement of the batch. |
| A6 | No list of past adjustments. Each adjustment is visible on each product's page. |
| A7 | A line whose counted number equals current stock writes nothing. If no line changes, the save fails ("No hay cambios de stock para guardar"). |
| A8 | All or nothing: one transaction for the whole batch. |
| A9 | The old nested page (`Web::Products::StockMovementsController`, its view and route) is deleted: unlinked, unstyled, and it lets anyone with access record a fake purchase or sale. The policy and the service stay. |
| A10 | Out of scope: a note per line, undoing an adjustment, several stock locations (`StockLocation.first!` as everywhere else), a list/detail of adjustments. |

## Data

- Migration: `add_reference :stock_movements, :user, null: true, foreign_key: true`. Existing rows stay null.
- `StockMovement belongs_to :user, optional: true`.
- `Inventory::AdjustStock.call(..., user: nil)` — new optional keyword, written to the movement. Every existing caller is unchanged.

## Service — `Inventory::SetCountedStock`

`Inventory::SetCountedStock.call(user:, note:, lines:)` where `lines` is an array of `{ product_id:, counted: }`. Returns `Result`; `record` is the array of movements written.

1. Validate (Spanish messages, first failure wins):
   - note blank → "El motivo es obligatorio"
   - no lines → "Agregá al menos un producto"
   - a `counted` that is blank, not an integer, or negative → "El stock real de <product name> debe ser un número entero mayor o igual a 0" ("producto <id>" if the product cannot be found)
   - a `counted` above 1.000.000 → "El stock real de <product name> es demasiado grande"
   - the same product twice → "<product name> está repetido"
2. In one `ActiveRecord::Base.transaction`, for each line:
   - `product = Product.lock.find(product_id)` (default scope: a soft-deleted product is not found → "Producto no encontrado"; an inactive product is allowed)
   - `difference = counted - product.stock_movements.sum(:quantity)` — against the ledger, not the cached column, so a drifted `current_stock` still ends at the count (changed after review on 2026-09-30)
   - if `difference != 0`: `Inventory::AdjustStock.call(product:, stock_location: StockLocation.first!, movement_type: :adjustment, quantity: difference, note:, user:, allow_negative: true)` (AdjustStock's floor reads the cached column; the target is the count, never negative); a failed `Result` raises and rolls back everything.
3. No movement written → fail with "No hay cambios de stock para guardar" (nothing persisted).

The lock only serializes when the caller is inside this transaction, which it always is here.

## Web

- Route: `resources :stock_adjustments, only: [:new, :create]` inside the `/web` namespace.
- `Web::StockAdjustmentsController` (thin):
  - `new`: `authorize Product, :adjust_stock?`; with `params[:product_id]`, preload that product as the first line.
  - `create`: `authorize Product, :adjust_stock?`; build `lines` from `params[:lines]` (`product_id`, `counted`), call the service with `current_user` and `params[:note]`.
    - success → `redirect_to new_web_stock_adjustment_path, notice: "Ajuste guardado: N producto(s) actualizado(s)"` (N = movements written; correct Spanish singular/plural).
    - failure → re-render `new` with 422, keeping the lines and the reason; each line's current stock is re-read from the database.
- Unauthorized (vendedor, caja) → the existing `ApplicationController` Pundit redirect with flash, for both actions.

## UI (see wireframes)

- **Sidebar:** "Ajuste de stock" under "Productos", only when `policy(Product).adjust_stock?`.
- **Product page, "Stock Actual" card:** "Ajustar stock" button, only when `policy(@product).adjust_stock?`, linking to `new_web_stock_adjustment_path(product_id: @product.id)`.
- **Adjustment page**, HAML, per `docs/UI_DESIGN_SPEC.md`:
  - Header "Ajuste de stock" + one-line hint.
  - "Productos" card: `product-search` with `dimOutOfStock: false`; table SKU · Producto · Stock actual (read-only) · Stock real (integer input, starts empty) · Diferencia (live: `+4`, `−3`, `sin cambio`) · remove. Counter "N productos · M con cambio". Empty state "Buscá un producto para agregarlo al ajuste."
  - Picking a product already in the table focuses its row instead of duplicating it. Picking a new one appends a row and focuses "Stock real".
  - Reason card: "Motivo" input (required), "Guardado por: <user.name>", "Cancelar" (back to the product page when entered from it, else Productos) and "Guardar ajuste" — disabled until there is a reason and at least one line with a change.
  - New Stimulus controller `stock-adjustment-lines`, same shape as `invoice-lines` (renders rows with a hidden `lines[N][product_id]` and the visible `lines[N][counted]` input; initial lines from a JSON value for the preload and the 422 re-render).
- **Product page, "Movimientos de Stock Recientes":** a movement with a `user` reads "<user.name> · <note>". Movements without a user render exactly as today. `ProductsController#show` adds `:user` to its `includes`.

## Wireframe element mapping

| Element | Status | Backed by / cost |
|---|---|---|
| Sidebar item, product-page button, access | Mapped | `ProductPolicy#adjust_stock?` + its spec |
| Product search | Mapped | `product-search` controller, `GET /web/products/search` (active products only; an inactive one is reachable from its product page) |
| Lines table, live difference | Gap | New `stock-adjustment-lines` Stimulus controller |
| Save (all or nothing, difference at save time) | Gap | New `Inventory::SetCountedStock` |
| Who did it | Gap | Migration `stock_movements.user_id`; `AdjustStock` `user:` keyword |
| "user · reason" on the product page | Gap | One view branch + `includes(:user)` |
| Route + controller | Gap | `Web::StockAdjustmentsController#new/create` |
| Old nested page | Removed | Controller, view, route |

No conflicts: stock moves only through `Inventory::AdjustStock`; services return `Result`; Pundit gates both actions; the controller only parses params, calls the service and renders.

## Testing

- `spec/services/inventory/set_counted_stock_spec.rb`: raise, lower, to zero; an unchanged line writes nothing; all unchanged fails; each validation message; a soft-deleted product fails; an inactive product works; rollback when one line's `AdjustStock` fails (no movement written, stock unchanged); the difference is computed against stock at save time (stock changes between building the lines and the call, the result still equals `counted`); every movement carries `user`, `note`, `movement_type: adjustment`, no reference.
- `spec/services/inventory/adjust_stock_spec.rb`: `user:` is written when given, null when omitted.
- `spec/requests/web/stock_adjustments_spec.rb`: admin `new` (with and without `product_id`), admin `create` success → redirect + flash + stock; 422 keeps lines and reason; vendedor and caja rejected on both actions.
- `spec/requests/web/products_spec.rb`: an adjustment movement renders "<user.name> · <note>"; the "Ajustar stock" button shows for admin only.
- One system spec: search a product, type the counted number, see the live difference, save, see the flash and the new stock.
- Stock is seeded through `purchase` movements (a factory `current_stock:` with no movement is overwritten by the recalculation).

## Docs

`WORKING_CONTEXT.md`: stock now also moves through admin adjustments (page, service, `user_id`); the old nested page is gone. `docs/TESTING_GUIDE.md`: add `SetCountedStock` to the "Out of scope on purpose" list next to `DeductLineStock` / `RestoreLineStock` (quantities, not money).

## Constraints (binding; copy into the plan's Global Constraints)

- Stock is never written directly: every change goes through `Inventory::AdjustStock` → `StockMovement` → `product.recalculate_current_stock!`.
- UI follows `docs/UI_DESIGN_SPEC.md`: slate-based and sober, no saturated accents as decoration.
- The UI shows the operator's mental model (counted units, "sin cambio"), not persistence internals (deltas, movement types beyond the existing badge).
- Reuse before writing new: `product-search`, the `invoice-lines` shape, `ProductPolicy#adjust_stock?`, `Inventory::AdjustStock`, existing helpers.
- HAML only; UI text in Spanish; code, comments, specs, docs and commit messages in English.
- Code comments minimal and only where needed; never cite AGENTS.md, specs or other docs from code.
- Commits: `type(feat_34): title`, body in bullets, English, no attribution lines (no Co-Authored-By, no Claude mention). The owner squashes the branch at the end.
- Implementers never dispatch subagents.
