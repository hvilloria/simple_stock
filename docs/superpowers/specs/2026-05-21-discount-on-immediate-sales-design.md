# Descuento en Ventas Inmediatas — Design Spec

**Date:** 2026-05-21
**Feature:** feat_08-discount-on-immediate-sales

## Context

Al vender, le preguntamos al cliente si necesita factura. Para ciertos casos le ofrecemos un descuento — típicamente 10% cuando el cliente no la pide. Hoy el sistema no permite registrar ese descuento: el operador tiene que hacer el cálculo a mano y poner un `unit_price` modificado, lo cual pierde el dato del precio real y del descuento aplicado.

Este feature agrega un descuento global por venta inmediata (0% / 5% / 10%) que se aplica al crear la orden y se persiste tanto en cada `order_item` como en un total original a nivel de la orden para auditoría.

**Importante:** este spec cubre **solo** las ventas inmediatas. El descuento en ventas a crédito (que se aplica al momento de cobrar, con porcentajes por item y un tope diferente del 20%) se diseña aparte en feat_09.

---

## Scope

### In scope

1. Migration: agregar `order_items.discount_percent` y `orders.original_total_amount`
2. Modelo `OrderItem`: validación del rango de `discount_percent` y reglas según `order.order_type`
3. Modelo `Order`: setear `original_total_amount` al crear, validación `original_total_amount >= total_amount`
4. Servicio `Sales::CreateOrder`: aceptar `discount_percent` global, distribuirlo a cada item, calcular `total_amount` post-descuento, guardar `original_total_amount`
5. Form `web/orders/new`:
   - Nueva card "Descuento" entre "Productos" y "Detalle de Pago" con dropdown `0% / 5% / 10%`
   - Reordenar columna izquierda a: **Cliente → Productos → Descuento → Detalle de Pago** (extraer "Detalle de Pago" del card de Cliente)
   - Stimulus `order-form` extendido para recalcular total y disparar validación de pagos al cambiar el descuento
   - Resumen derecho: bloque "Subtotal (tachado) / Descuento −X%" debajo del Total, visible solo cuando descuento > 0
   - Ocultar el card "Descuento" cuando `order_type = credit`
6. Vista `web/orders/show`:
   - Footer de la tabla "Productos Vendidos": agregar filas "Subtotal" y "Descuento −X%" cuando descuento > 0
   - Resumen derecho: agregar líneas "Subtotal" y "Descuento −X%" debajo de Items/Cantidad cuando descuento > 0
7. Specs:
   - `spec/models/order_item_spec.rb` — validaciones de `discount_percent`
   - `spec/models/order_spec.rb` — `original_total_amount` validación
   - `spec/services/sales/create_order_spec.rb` — extender con casos de descuento (0%, 5%, 10%, intento >10% en immediate, intento >0 en credit)
   - `spec/requests/web/orders_spec.rb` — request spec del create con descuento

### Out of scope

- Descuento en ventas a crédito (feat_09)
- Descuento por línea individualizado en ventas inmediatas — siempre es global y se reparte a cada item
- Migración de órdenes históricas: la app no tiene órdenes en producción todavía (solo está corriendo el módulo de facturas a proveedores). La migración backfillea cualquier orden de seeds/dev con `original_total_amount = total_amount`
- Cambiar la lógica de cancel: `Sales::CancelOrder` no necesita cambios (restock por cantidad, no por monto)
- Sales ledger: no toca CSV imports
- Dashboard / order index: ya leen `total_amount`, que sigue siendo el campo de verdad — sin cambios
- System / browser specs

---

## Architecture

### Schema migration

```ruby
class AddDiscountToOrdersAndItems < ActiveRecord::Migration[7.2]
  def up
    add_column :order_items, :discount_percent, :decimal, precision: 5, scale: 2, default: 0, null: false
    add_column :orders, :original_total_amount, :decimal, precision: 10, scale: 2

    # Backfill any existing rows (seeds, dev) so original_total_amount mirrors total_amount.
    execute "UPDATE orders SET original_total_amount = total_amount WHERE original_total_amount IS NULL"

    change_column_null :orders, :original_total_amount, false
  end

  def down
    remove_column :orders, :original_total_amount
    remove_column :order_items, :discount_percent
  end
end
```

- `order_items.discount_percent` — % aplicado a esta línea. Decimal con precisión por si en el futuro permitimos valores no-enteros. Default `0`, NOT NULL.
- `orders.original_total_amount` — total **pre-descuento**, seteado al crear la orden. NOT NULL después del backfill (no hay órdenes en producción, las de seeds/dev quedan con `original = total`).
- `orders.total_amount` — **no cambia su semántica**: sigue siendo el total vigente (post-descuento). Todo el resto del sistema lo lee sin cambios.

### Model: `OrderItem` (cambios)

```ruby
class OrderItem < ApplicationRecord
  belongs_to :order
  belongs_to :product

  validates :quantity, numericality: { greater_than: 0 }
  validates :unit_price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :discount_percent,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 20 }
  validate :discount_within_order_type_cap

  private

  def discount_within_order_type_cap
    return if order.nil? || discount_percent.nil? || discount_percent.zero?

    if order.credit_order_type?
      errors.add(:discount_percent, "no permitido en ventas a crédito")
    elsif order.immediate_order_type? && discount_percent > 10
      errors.add(:discount_percent, "no puede exceder 10% en ventas inmediatas")
    end
  end
end
```

El tope superior absoluto (20) se valida con `less_than_or_equal_to`. La regla específica por `order_type` se valida en el callback. Cuando feat_09 esté listo, ese callback se actualiza para permitir hasta 20 en credit.

### Model: `Order` (cambios)

```ruby
class Order < ApplicationRecord
  # ... existing code
  validates :original_total_amount,
            presence: true,
            numericality: { greater_than_or_equal_to: 0 }
  validate :original_total_at_least_current_total

  private

  def original_total_at_least_current_total
    return if original_total_amount.nil? || total_amount.nil?
    if original_total_amount < total_amount
      errors.add(:original_total_amount, "no puede ser menor al total actual")
    end
  end
end
```

`calculate_total!` queda igual (lee `unit_price` × `quantity` desde items; el descuento se aplica antes de llamar). El método se sigue usando si en algún punto necesitamos recalcular.

### Service: `Sales::CreateOrder` (cambios)

Entrada: agregar parámetro `discount_percent` (decimal, default 0). En la práctica viene del form `web/orders/new` como un único valor global.

Pseudocódigo del cambio:

```ruby
def initialize(customer:, items:, order_type:, user:, discount_percent: 0, ...)
  @discount_percent = discount_percent.to_d
  # ...
end

def call
  ActiveRecord::Base.transaction do
    validate!
    create_order  # total_amount still computed the existing way at this point
    create_items_with_discount
    recalculate_order_totals
    create_stock_movements
    create_payments

    Result.new(success?: true, record: @order, errors: [])
  end
  # rescue blocks unchanged
end

private

def validate!
  # existing validations...
  if @order_type == "credit" && @discount_percent > 0
    raise ValidationError, "No se permite descuento en ventas a crédito"
  end
  if @order_type == "immediate" && @discount_percent > 10
    raise ValidationError, "Descuento máximo permitido en ventas inmediatas: 10%"
  end
end

def create_items_with_discount
  @items.each do |item|
    @order.order_items.create!(
      product_id: item[:product_id],
      quantity: item[:quantity],
      unit_price: item[:unit_price],
      discount_percent: @discount_percent
    )
  end
end

def recalculate_order_totals
  original = @order.order_items.sum { |i| i.quantity * i.unit_price.to_d }
  current  = @order.order_items.sum { |i| i.quantity * i.unit_price.to_d * (1 - i.discount_percent.to_d / 100) }
  @order.update!(
    original_total_amount: original,
    total_amount: current.round(2)
  )
end
```

**Invariante:** `total_amount = sum(qi * pi * (1 - di/100))` y `original_total_amount = sum(qi * pi)`. La regla del sistema "sum(payments) == total_amount" en immediate sigue funcionando automáticamente porque `total_amount` ya es post-descuento.

`from_paper` orders: no enforce especial — el descuento se aplica igual sobre los `unit_price` cargados (aunque la UI por defecto muestra 0%).

### Controller: `Web::OrdersController#create` (cambios)

```ruby
def create
  result = Sales::CreateOrder.call(
    customer: resolved_customer,
    items: parsed_items,
    order_type: order_params[:order_type],
    discount_percent: order_params[:discount_percent].presence || 0,
    user: current_user,
    # ... el resto igual
  )
  # ...
end

private

def order_params
  params.require(:order).permit(:customer_id, :order_type, :channel, :discount_percent, ...)
end
```

---

## UI

### Form `web/orders/new`

Layout izquierda **reordenado** en este orden:

1. **Información del Cliente** — tipo de venta + cliente + canal. Sin "Detalle de Pago" adentro (sale a su propio card).
2. **Productos** — search + lista de items. Sin columna ni indicador per-línea del descuento. Precios y subtotales se muestran como pre-descuento; el cálculo final vive en el Resumen.
3. **Descuento** — card nuevo: heading "Descuento", helper text "Se aplica al total de la venta. Máx. 10% en ventas inmediatas.", dropdown `0% / 5% / 10%` a la derecha. **Oculto cuando `order_type = credit`** (Stimulus toggle).
4. **Detalle de Pago** — el bloque que hoy está adentro de "Cliente" sale como card propio.

Resumen derecho (sticky):

- **Total** grande arriba — post-descuento, cambia en vivo.
- Cuando `discount_percent > 0`, agregar entre el Total y el bloque de Items:
  - "Subtotal" — gris, tachado (`text-slate-500 line-through`)
  - "Descuento −X%" — amber-700, monto negativo en bold
- Cuando `discount_percent = 0`, ese bloque no se renderiza (no ocupa espacio).
- El bloque "Cobrás ahora / A cuenta corriente" (feat_07) sigue solo en credit, sin cambios.

### Stimulus `order_form_controller.js`

Nuevos targets:
- `discountSelect` — el `<select>` del nuevo card
- `discountCard` — el contenedor del card "Descuento" (para toggle hide/show)
- `summarySubtotal` — `<span>` en el Resumen para el subtotal tachado
- `summaryDiscount` — `<span>` para el descuento −$Y
- `summaryDiscountRow` — el contenedor del bloque (para hide cuando 0%)

Nuevos métodos / extensiones:
- `discountChanged()` — al cambiar el dropdown: recalcular `total` (=`subtotal * (1 - d/100)`), actualizar `totalTarget`, actualizar `summarySubtotalTarget` y `summaryDiscountTarget`, mostrar/ocultar `summaryDiscountRowTarget`, disparar `updatePaymentTotal()` para re-validar el bloque de pagos.
- `applyPaymentMode(orderType)` — extender lo existente: si `credit`, agregar `discountCardTarget.classList.add("hidden")` y resetear `discountSelectTarget.value = "0"` + re-disparar `discountChanged()`. Si `immediate`, remove hidden.
- `updateItemsTotals()` (existente, que recalcula subtotales al agregar/quitar items) — al final, llamar a `discountChanged()` para que el descuento se reaplique al nuevo subtotal.

### Vista `web/orders/show`

**Card "Productos Vendidos":** sin cambios en la tabla en sí. Cambia el `<tfoot>`:

```haml
%tfoot.bg-gray-50
  - if @order.discount_amount > 0
    %tr
      %td.px-6.py-2.text-right.text-sm.text-slate-500{colspan: "5"} Subtotal
      %td.px-6.py-2.text-right.text-sm.text-slate-500.line-through= currency_ar(@order.original_total_amount)
    %tr
      %td.px-6.py-2.text-right.text-sm.text-amber-700{colspan: "5"}
        = "Descuento −#{@order.discount_percent_display}%"
      %td.px-6.py-2.text-right.text-sm.text-amber-700.font-semibold= "−#{currency_ar(@order.discount_amount)}"
  %tr.border-t.border-gray-200
    %td.px-6.py-4.text-right.text-base.font-bold.text-gray-900{colspan: "5"} Total
    %td.px-6.py-4.text-right.text-xl.font-bold.text-gray-900= currency_ar(@order.total_amount)
```

`Order` necesita dos helpers:

```ruby
def discount_amount
  original_total_amount - total_amount
end

# Assumes all items share the same discount_percent (true for feat_08 immediate sales).
# Revisit this helper in feat_09 when credit orders introduce per-item discounts.
def discount_percent_display
  order_items.first&.discount_percent.to_i
end
```

**Card "Resumen" derecho:** dentro del bloque entre el Total y el "Análisis de Costos", agregar (cuando `discount_amount > 0`):

```haml
.flex.justify-between.text-sm
  %span.text-gray-600 Subtotal
  %span.text-gray-500.line-through= currency_ar(@order.original_total_amount)
.flex.justify-between.text-sm
  %span.text-amber-700= "Descuento −#{@order.discount_percent_display}%"
  %span.font-semibold.text-amber-700= "−#{currency_ar(@order.discount_amount)}"
```

La línea "Subtotal" que existe hoy (que duplica el total) se reemplaza por este bloque condicional. Cuando no hay descuento, no se muestra ninguna de esas líneas (el Total grande arriba ya alcanza).

---

## Validaciones / reglas de negocio

1. **`discount_percent` por item:** 0 ≤ d ≤ 20 (constraint duro del modelo). El servicio agrega tope contextual: ≤10 en immediate, =0 en credit.
2. **`original_total_amount ≥ total_amount`** (sanity check del modelo).
3. **`credit + discount > 0` = error** del servicio en feat_08. En feat_09 esto cambia.
4. **El total de pagos debe igualar `total_amount`** en immediate — regla existente, sigue funcionando porque `total_amount` ya es post-descuento.
5. **Stock se valida contra `quantity`, no contra monto** — regla existente, sin cambios.

---

## Testing

### `spec/models/order_item_spec.rb` (extender)

```
validations
  - is invalid with discount_percent < 0
  - is invalid with discount_percent > 20
  - is invalid with discount_percent > 10 when order is immediate
  - is invalid with discount_percent > 0 when order is credit
  - is valid with discount_percent = 10 when order is immediate
  - is valid with discount_percent = 0 in any order_type
```

### `spec/models/order_spec.rb` (extender)

```
validations
  - is invalid without original_total_amount
  - is invalid when original_total_amount < total_amount

#discount_amount
  - returns original_total_amount - total_amount
  - returns 0 when no discount was applied (original == total)
```

### `spec/services/sales/create_order_spec.rb` (extender)

```
.call with discount_percent
  - applies discount_percent to all created order_items
  - persists original_total_amount = sum(qty * unit_price)
  - persists total_amount = sum(qty * unit_price * (1 - d/100)) rounded
  - returns failure when order_type=credit and discount_percent > 0
  - returns failure when order_type=immediate and discount_percent > 10
  - succeeds with discount_percent = 0 (no change to today's behavior)
  - succeeds with discount_percent = 10 and exact payment matching new total
  - returns failure when payments sum != new total (existing rule, with discounted total)
```

### `spec/requests/web/orders_spec.rb` (extender)

```
POST /web/orders with discount_percent
  - creates order with correct total and original_total_amount on valid input
  - re-renders new with error on discount > 10 in immediate
  - re-renders new with error on discount > 0 in credit
```

---

## Files to modify / create

**Create:**

- `db/migrate/YYYYMMDDHHMMSS_add_discount_to_orders_and_items.rb`

**Modify:**

- `app/models/order_item.rb` — validación de `discount_percent`
- `app/models/order.rb` — validación de `original_total_amount`, helpers `discount_amount` y `discount_percent_display`
- `app/services/sales/create_order.rb` — aceptar `discount_percent`, distribuirlo, recalcular totales
- `app/controllers/web/orders_controller.rb` — pasar `discount_percent` al service
- `app/views/web/orders/new.html.haml` — reordenar cards, extraer "Detalle de Pago" del card de Cliente, agregar card "Descuento", agregar bloque "Subtotal/Descuento" al Resumen
- `app/javascript/controllers/order_form_controller.js` — nuevos targets y métodos para descuento
- `app/views/web/orders/show.html.haml` — agregar filas de Subtotal/Descuento al `tfoot` de Productos y al Resumen derecho
- `spec/models/order_item_spec.rb`
- `spec/models/order_spec.rb`
- `spec/services/sales/create_order_spec.rb`
- `spec/requests/web/orders_spec.rb`
- `WORKING_CONTEXT.md` — documentar el nuevo campo, el comportamiento de `Sales::CreateOrder`, el comportamiento del form
- `docs/DEVELOPMENT_GUIDE.md` — sección "Sales" podría mencionar que las ventas inmediatas soportan descuento global hasta 10% (cuestión menor; no es obligatorio actualizarlo aquí si la regla queda autoexplicativa en el código)

---

## Known limitations

### Descuento solo global en immediate

En este feature, todas las líneas de una orden inmediata comparten el mismo `discount_percent`. No hay UI para descuentos por línea distintos. Si en el futuro el negocio quiere granularidad item-por-item en ventas inmediatas (ej: 5% en un repuesto, 10% en otro de la misma venta), habrá que reabrir esto.

### feat_09 comparte el schema pero cambia las reglas

Cuando se implemente feat_09, las validaciones del modelo en `OrderItem` cambian (subir el tope a 20 en credit) y el flujo de mutación del descuento se mueve a `Payments::AllocatePayment`. Este spec asume eso quedará para una iteración separada.

---

## Open questions

Ninguna pendiente. Decisiones tomadas:

- Tope 10% en immediate, validado en modelo + servicio
- Total post-descuento se persiste en `total_amount`; `original_total_amount` guarda el subtotal pre-descuento
- Discount se reparte por item internamente (`order_items.discount_percent` por línea), pero la UI lo trata como una decisión global
- Card "Descuento" se oculta cuando `order_type = credit` (descuento de credit va a feat_09)
- UI sobria: sin acentos de fondo en el card del descuento; el amber-700 queda solo en el texto del desglose del Resumen y en el `tfoot` del show
- Orden del form: Cliente → Productos → Descuento → Pago
- Form: dropdown global, no per-línea
- `orders/show`: solo el desglose al pie de la tabla (sin columna nueva)
