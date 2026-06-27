# Edición de producto — Design

> Fecha: 2026-06-26
> Estado: aprobado (pendiente de plan de implementación)

## Goal

Activar la edición de productos vía UI web. Hoy `edit`/`update` están **ruteados** (`config/routes.rb`) y la **policy ya define** `edit?`/`update?`, pero faltan: la acción en el controller, la vista `edit`, y que el `_form` compartido postee a la URL correcta. El botón "Editar Producto" ya existe en `show` pero está muerto.

El disparador: durante el feature de *manual-pricing-for-orders* se asumió que no hacía falta editar productos. En la práctica sí: hay que poder corregir precio, marca, origen y demás datos de un producto ya creado.

## Contexto relevante

- **Roles:** `vendedor`, `caja`, `admin`.
- **Identidad de variante:** `sku + product_type + origin + brand`. La validación de unicidad del modelo `Product` se enforça **solo cuando `origin` está presente** (`if: -> { origin.present? }`).
- **Campos protegidos:** `current_stock` (solo vía `StockMovement` + `recalculate_current_stock!`) y `cost_unit` (lo recalcula `recalculate_average_cost!` al confirmar compras).
- **Manual-pricing write-back:** `Sales::CreateOrder` escribe el precio tipeado de vuelta en `product.price_unit` en cada venta. El precio de catálogo es **fluido** por diseño.

## Decisiones

### 1. Write-back se mantiene
El precio sigue siendo fluido: cada venta puede pisar `product.price_unit` vía write-back. La pantalla de edición **no** congela el precio; fija el "precio de partida" del próximo pedido. No hay choque mecánico — edición y write-back escriben la misma columna. Para que el usuario no espere que el precio quede fijo, el campo "Precio de Venta" lleva una **nota** en modo edición aclarando que una venta posterior puede sobrescribirlo.

### 2. Campos editables / bloqueados
- **Editables:** los campos que el `_form` ya renderiza — `name`, `brand`, `origin`, `product_type`, `price_unit`, `cost_unit`, `cost_currency`, `active` (más `category`, ya permitido aunque sin campo visible). **No se expande el form** con campos nuevos (`location_code` queda fuera de alcance).
- **Bloqueados:**
  - `sku` — ancla de identidad OEM. Se muestra `readonly` (visible, no editable) y se **excluye de los params de update**.
  - `current_stock` — no está en el form; sigue gestionándose por movimientos de inventario.

### 3. Identidad de variante
Editar `origin`/`product_type`/`brand` está permitido. Si un cambio colisiona con otra variante del mismo `sku`, la **validación de unicidad existente** (activa cuando hay `origin`) lo bloquea y muestra el error en el form. No se agrega lógica nueva — la red de seguridad ya existe.

### 4. Permisos
`edit?`/`update?` pasan de **admin-only** a **admin + vendedor**. `caja` queda afuera. `create?`/`destroy?` siguen siendo **solo admin** (sin cambios).

## Cambios técnicos (mínimos)

1. **`app/policies/product_policy.rb`**
   - `update?` → `user.admin? || user.vendedor?` (`edit?` ya delega en `update?`).
   - `create?`/`destroy?`/`adjust_stock?` sin cambios (siguen admin-only).

2. **`app/controllers/web/products_controller.rb`**
   - `edit`: `@product = Product.find(params[:id])` + `authorize @product`.
   - `update`: find + authorize + `@product.update(sanitized_product_params)` → redirect a `web_product_path` con notice; si falla, `render :edit, status: :unprocessable_entity`.
   - Reusar `sanitized_product_params` (ya parsea moneda AR vía `CurrencyParser`). **Excluir `sku`** de los params permitidos en update (p. ej. un `update_product_params` que haga `product_params.except(:sku)`, o un permit dedicado sin `:sku`).

3. **`app/views/web/products/_form.html.haml`**
   - URL del `form_with` resuelta por persistencia: `product.persisted? ? web_product_path(product) : web_products_path`.
   - `sku`: `readonly` y sin `autofocus` cuando `product.persisted?`.
   - Nota bajo "Precio de Venta" cuando `product.persisted?`: aclara que el precio se usa como punto de partida del próximo pedido y que una venta posterior puede sobrescribirlo (write-back).

4. **`app/views/web/products/edit.html.haml`** (nueva)
   - Espejo de `new.html.haml`: `content_for :page_title` + `render "form", product: @product`.

5. **`app/views/web/products/show.html.haml`**
   - Gatear el botón "Editar Producto" (línea ~13) con `policy(@product).edit?`.

## UI (debe respetar `docs/UI_DESIGN_SPEC.md`)

Por ser trabajo de front, se siguen las reglas del spec de UI. En la práctica esto es directo porque **reusamos el `_form` compartido**, que ya cumple las convenciones (cards `slate`, inputs sobrios, errores cerca del campo, submit primario claro). Puntos concretos:

- **Reuso antes que nuevo** (regla de consistencia): no se crea un form nuevo; se adapta el existente. `edit.html.haml` es espejo de `new.html.haml`.
- **Nota del precio** (modo edición): helper text quieto, estilo `text-xs text-slate-500` igual que la nota de costo ya presente — no un banner llamativo.
- **`sku` readonly**: mantener el estilo de input pero con apariencia deshabilitada coherente (mismo patrón sobrio, sin color fuerte), para que se lea claramente como no editable.
- Sin emojis nuevos, sin gradientes, sin variantes de botón nuevas. Acción primaria "Guardar Producto" como ya está.

## Limitaciones honestas (a documentar en WORKING_CONTEXT)

- `cost_unit` es editable, pero `recalculate_average_cost!` lo pisa al confirmar una compra. Hoy las compras corren por rake/seed (no hay UI web), así que en la práctica la edición manual de costo persiste hasta la próxima compra confirmada.
- `price_unit` editado se pisa con la próxima venta (write-back). Intencional; aclarado en la nota de UI.

## Testing

Request specs en `spec/requests/web/products_spec.rb` (o el existente):

- `GET edit`: admin → 200; vendedor → 200; caja → redirect (no autorizado).
- `PATCH update` happy-path: un vendedor cambia `name`/`brand`/`origin`/`price_unit` → cambios persisten, redirect a `show` con notice.
- `PATCH update` inválido (p. ej. `name` vacío) → re-render `edit` con 422.
- `PATCH update` con `sku` en params → el `sku` **no** cambia.
- Colisión de variante (cambiar `origin` para chocar con otra variante del mismo `sku`) → falla con error de unicidad, sin persistir.

## Fuera de alcance

- Editar `current_stock` (sigue por movimientos).
- Cualquier cambio al flujo de manual-pricing / write-back.
- Lista de precios por origen u otras mejoras de pricing.
- Permitir a `caja` editar productos.
