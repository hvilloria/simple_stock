# feat_10 — Separación vendedor / caja: nota de pedido + cobro

## Objetivo

Hoy el vendedor concentra toda la decisión de una venta: tipo, descuento y
detalle de pago. Esto no refleja el flujo real del negocio. Este feature lo
parte en dos roles:

- **Vendedor** arma una **nota de pedido**: cliente, productos, tipo
  (`immediate` o `credit`) y N° de talonario físico. Sin descuento ni pago.
- **Caja** cobra las notas **inmediatas** desde una pantalla propia:
  aplica descuento global (0-10%) y método(s) de pago.
- Las notas **a crédito** no pasan por caja: van directo al flujo existente
  de **cuentas por cobrar** (`Web::Customers::PaymentsController`,
  `Payments::AllocatePayment`), sin cambios funcionales — feat_09 intacto.

Como consecuencia, el estado `confirmed` se redefine: una orden está
`confirmed` cuando `outstanding_balance == 0`. Mientras le quede saldo
(sea immediate sin cobrar, sea credit con balance), queda `pending`.

## Reglas del negocio

1. **Quién decide qué:**
   - Vendedor: cliente, productos, `order_type`, `paper_number`.
   - Caja (solo immediate): descuento global, método(s) de pago.
   - Cobranza credit: sin cambios respecto a feat_09 (per-item discount en
     el primer cobro, multi-allocation).
2. **`paper_number` obligatorio en toda nota live nueva.** Hoy solo se
   exige para `source: from_paper`. Pasa a exigirse también para
   `source: live`. El vendedor lo escribe en el form al crear la nota.
3. **Estado inicial:** toda nota nace `pending`, sin importar el tipo.
4. **Promoción a `confirmed`:** automática cuando `outstanding_balance == 0`.
   - Immediate: al confirmar el cobro (caja).
   - Credit: cuando una allocation deja el saldo en 0.
5. **Descuento en cobro de inmediatas:** solo permitido si la totalidad se
   paga en efectivo. Si hay cualquier otro método o el efectivo no cubre
   el total, descuento forzado a 0%. Aplica tanto en frontend (Stimulus)
   como en backend (validación de servicio).
6. **Cancelación:**
   - Notas `pending` (cualquier tipo): cancelables por vendedor / caja / admin.
   - Notas `confirmed`: solo admin (comportamiento actual).
   - Caja debe confirmar (JS `confirm`) antes de cancelar.
7. **Stock:** sin cambios. Hoy las ventas no tocan stock (verificado en
   `Sales::CreateOrder` — solo valida disponibilidad, no crea
   `StockMovement`). Esto se mantiene; cualquier cambio queda para otro
   feature. `WORKING_CONTEXT.md` debe corregirse en este punto.

## Modelo de datos

### Migración 1 — agregar estado `pending` al enum

```ruby
# db/migrate/XXXX_add_pending_status_to_orders.rb
class AddPendingStatusToOrders < ActiveRecord::Migration[7.2]
  def change
    change_column_default :orders, :status, from: "confirmed", to: "pending"
  end
end
```

No hay backfill: confirmado con el usuario que no hay órdenes productivas.

### Migración 2 — `paper_number` requerido para live

Hoy la columna existe (`string`, nullable). Sigue nullable en BD por
compatibilidad con datos `from_paper` legacy que pudieran venir sin él
(no es el caso hoy pero no rompemos el esquema). La obligatoriedad se
fuerza a nivel de modelo (validation, no DB).

### Cambios en `Order`

```ruby
enum :status, {
  pending:   "pending",
  confirmed: "confirmed",
  cancelled: "cancelled"
}, suffix: true

# default ya viene del DB

validates :paper_number, presence: true
# (`source` solo admite `live` o `from_paper`, así que es siempre requerido)

scope :pending,   -> { where(status: "pending") }
scope :confirmed, -> { where(status: "confirmed") }
scope :active,    -> { where.not(status: "cancelled") } # ya existe

def outstanding_balance
  return 0 if cancelled_status?
  total_amount - payment_allocations.sum(:amount)
end
```

Cambios clave en `outstanding_balance`: deja de devolver 0 para immediate
y deja de filtrar por `credit_order_type?`. Ahora vale para ambos tipos.

### Promoción automática a `confirmed`

Encapsulada en `Order#refresh_status_from_balance!`:

```ruby
def refresh_status_from_balance!
  return if cancelled_status?
  new_status = outstanding_balance <= 0 ? "confirmed" : "pending"
  update!(status: new_status) if status != new_status
end
```

Se llama desde los dos servicios de cobro (`Payments::AllocatePayment` y
el nuevo `Payments::CollectSaleNote`) **dentro de la transacción**, después
de crear allocations.

### Scopes y cálculos derivados

- **`Customer#current_balance`:** hoy filtra `credit_orders` confirmadas y
  resta allocations. Pasa a filtrar `credit_orders.where(status:
  %w[pending confirmed])` (i.e., `active`). Misma fórmula, distinto
  filtro.
- **`Customer.with_outstanding_balance`:** misma corrección.
- **`Dashboard#index` "sales today":** hoy suma `confirmed.where(created_at:
  Date.today.all_day)`. Pasa a `active` (incluye `pending` recién creadas
  y `confirmed` ya cobradas del día).
- **`Web::Customers::PaymentsController#new` (cuentas por cobrar):** hoy
  filtra `credit + confirmed + balance > 0`. Pasa a `credit + pending`
  (equivalente, más directo).

## Capa de servicio

### `Sales::CreateOrder` — simplificación

**Salen:**
- Parámetro `payments:` y todo el bloque `validate_payments` / `create_payments`.
- Parámetro `discount_percent:` y `validate_discount`.
- `PAYMENT_SUM_TOLERANCE`.

**Cambios:**
- `Order.create!(..., status: "pending")` en lugar de `confirmed`.
- `total_amount == original_total_amount == calculate_total` (sin descuento
  aplicado al crear; `OrderItem.discount_percent: 0`).
- Acepta `paper_number:` como obligatorio para `source: live` también.

**Firma final:**

```ruby
Sales::CreateOrder.call(
  customer:, items:, order_type:,
  channel: nil, source: "live",
  sale_date: nil, paper_number:   # ← ahora obligatorio para live
)
```

### `Payments::AllocatePayment` — promoción de estado

Una sola adición al final de la transacción, después de crear allocations:

```ruby
@orders_touched.each(&:refresh_status_from_balance!)
```

`@orders_touched` = orders únicas referenciadas en `allocations`. Resto del
servicio (per-item discounts, agrupación por método de pago, validaciones)
queda intacto.

### `Payments::CollectSaleNote` — nuevo servicio (cobro de inmediatas)

Cobra una nota immediate pending. Único punto de entrada para la pantalla
de caja.

```ruby
Payments::CollectSaleNote.call(
  order:,                  # Order — debe ser immediate + pending
  payment_date: Date.today,
  discount_percent: 0,     # 0, 5 o 10 (cap inmediatas)
  tenders: [               # multi-fila método+monto
    { payment_method: "cash",     amount: 50_000 },
    { payment_method: "transfer", amount: 39_300 }
  ]
)
```

Reglas en orden:

1. Validar `order.immediate_order_type? && order.pending_status?`.
2. Validar `discount_percent ∈ {0, 5, 10}`.
3. Validar cada tender: `payment_method ∈ PAYMENT_METHODS`, `amount > 0`.
4. Calcular `new_total = order.original_total_amount * (1 - discount_percent/100)`.
5. **Regla cash-only:** si `discount_percent > 0`, todos los tenders deben
   ser `cash` y `SUM(tenders.amount) == new_total` (tolerancia 0.01).
   En caso contrario, `Result.failure?` con
   `["Descuento solo permitido si el total se paga en efectivo"]`.
6. Validar `SUM(tenders.amount) == new_total` (tolerancia 0.01).
7. Transacción:
   - Si `discount_percent > 0`: aplicar a cada `order_item.discount_percent`
     (global → per-item, igual que feat_08 hoy en `Sales::CreateOrder`) y
     `order.update!(total_amount: new_total)`.
   - Por cada tender: crear `Payment` (`customer`, `amount`,
     `payment_method`, `payment_date`) + `PaymentAllocation` (`payment`,
     `order`, `amount`).
   - `order.refresh_status_from_balance!` → `confirmed`.
8. `Result.new(success?: true, record: order, errors: [])`.

### `Sales::CancelOrder` — sin cambios funcionales

Sigue funcionando. Para notas `pending` sin allocations, el bloque
`@order.payment_allocations.destroy_all` es no-op. Se actualiza la policy
para permitir vendedor/caja/admin (ver más abajo).

## Capa de controlador

### `Web::OrdersController` (vendedor)

- `#create`: deja de pasar `payments:` y `discount_percent:`. Pasa
  `paper_number:` (ahora del form). Redirige a `show` con flash
  "Nota #N creada, pendiente de cobro".
- `#cancel`: ahora puede ser invocado por vendedor también si la orden
  está `pending` (vía policy).
- `#index`: sigue mostrando todas las orders (con badge de estado).

### `Web::SaleNotesController` (caja, nuevo)

```ruby
# config/routes.rb
resources :sale_notes, only: [:index] do
  resource :payment, only: [:new, :create],
                     controller: "sale_notes/payments"
  member do
    post :cancel
  end
end
```

URLs:
- `GET  /web/sale_notes` → listado (pending immediate).
- `GET  /web/sale_notes/:id/payment/new` → form de cobro.
- `POST /web/sale_notes/:id/payment` → submit → `Payments::CollectSaleNote`.
- `POST /web/sale_notes/:id/cancel` → `Sales::CancelOrder`.

```ruby
class Web::SaleNotesController < Web::ApplicationController
  def index
    @notes = Order.immediate.pending.order(created_at: :asc)
    authorize Order  # via SaleNotePolicy
  end

  def cancel
    @order = Order.find(params[:id])
    authorize @order, :cancel_pending?
    result = Sales::CancelOrder.call(order: @order)
    # flash + redirect
  end
end
```

```ruby
class Web::SaleNotes::PaymentsController < Web::ApplicationController
  def new
    @order = Order.immediate.pending.find(params[:sale_note_id])
    authorize @order, :collect?
  end

  def create
    @order = Order.immediate.pending.find(params[:sale_note_id])
    authorize @order, :collect?

    result = Payments::CollectSaleNote.call(
      order: @order,
      discount_percent: params[:discount_percent].to_i,
      tenders: parsed_tenders
    )

    if result.success?
      redirect_to web_sale_notes_path, notice: "Nota #{@order.id} cobrada"
    else
      flash.now[:alert] = result.errors.join(", ")
      render :new, status: :unprocessable_entity
    end
  end

  private

  def parsed_tenders
    Array(params[:tenders]).map do |_, row|
      {
        payment_method: row[:payment_method],
        amount:         row[:amount].to_s.gsub(".", "").gsub(",", ".").to_f
      }
    end.reject { |t| t[:amount] <= 0 }
  end
end
```

### Policies

```ruby
# OrderPolicy
def cancel?
  user.admin?  # solo admin puede cancelar confirmed
end

def cancel_pending?
  record.pending_status? && (user.vendedor? || user.caja? || user.admin?)
end

# SaleNotePolicy (puede vivir como OrderPolicy con métodos extra)
def index?  = user.caja? || user.admin?
def collect? = (user.caja? || user.admin?) && record.pending_status?
```

## Capa UI

Mockups validados en sesión de brainstorming están guardados en
`.superpowers/brainstorm/`. Resumen:

### Form de nota (vendedor) — `app/views/web/orders/new.html.haml`

Se eliminan las cards **Descuento** y **Detalle de Pago**. Queda:
- Cliente
- Tipo de venta (immediate / credit)
- **N° de talonario** (nuevo input requerido)
- Productos
- Submit

Validación cliente↔tipo se mantiene (mostrador no admite credit).

### Listado de notas (caja) — `app/views/web/sale_notes/index.html.haml`

- Título "Notas de pedido", subtítulo "Pendientes de cobro".
- Sin barra de búsqueda, sin contador, sin hora, sin nombre de cliente.
- Card único `rounded-2xl` con filas separadas por border. Cada fila:
  `Talonario · N ítems · Total · [Cobrar]`.
- Talonario es el dato dominante (`text-xl font-semibold`).
- Botón Cobrar = primario (slate-900).

### Form de cobro (caja) — `app/views/web/sale_notes/payments/new.html.haml`

Layout 2 columnas (1fr / 360px):

**Izq:**
- Card "Productos" read-only (tabla simple: producto, cant, p.unit, subtotal).
- Card "Descuento": dropdown `0% / 5% / 10%`. Deshabilitado + helper en
  rojo cuando la regla cash-only no se cumple.
- Card "Detalle de pago": filas método + monto (currency-input AR),
  botón "+ Agregar método".

**Der (sticky):**
- Resumen: subtotal, descuento, total a cobrar, suma de pagos, diferencia.
- Botón primario "Confirmar cobro" (slate-900).
- Botón secundario "Cancelar nota" (con `confirm` JS antes de POST).

### Sidebar

Nueva entrada **"Notas de pedido"** visible para `caja` y `admin`. Va
junto a "Cuentas por cobrar" (también de caja).

### Stimulus (`sale_note_payment_controller.js` — nuevo)

Targets: `discountSelect`, `tenderRow`, `tenderMethod`, `tenderAmount`,
`subtotal`, `discountLine`, `total`, `paidSum`, `difference`,
`submitButton`, `discountHelper`.

Acciones:
- `tenderChanged` / `discountChanged` → recalcula resumen.
- `evaluateCashOnly` → si hay tender ≠ cash o suma cash < new_total,
  fuerza `discountSelect.value = "0"` + `disabled = true` + muestra
  `discountHelper`. Si todo es cash y suma == new_total, habilita.
- `addTender` / `removeTender` → manipulación filas.
- Inputs de monto usan `data-controller="currency-input"` (formato AR
  blur/focus, igual que `_form` de productos).

### `app/views/web/orders/new.html.haml` — limpieza

Quitar markup de las cards Descuento y Detalle de Pago.
Agregar input `paper_number` requerido. Simplificar
`app/javascript/controllers/order_form_controller.js`: borrar todos los
targets/acciones de descuento y pago (`paymentSection*`, `paymentRow*`,
`discountSelect`, `discountCard`, `summaryDiscount*`, etc.); mantener
items/total/orderType/customer.

## Migración de datos

Ninguna. Confirmado con el usuario que no hay órdenes en producción.

## Out of scope

- **Retrofit de `currency-input` en `web/customers/payments/new.html.haml`**
  → mini-feature aparte (feat_11). Este spec garantiza que el cobro nuevo
  nace con el patrón correcto; barrer la app vieja queda para después.
- Stock movements al vender (hoy no se aplican; cualquier cambio en
  manejo de inventario en el momento de venta queda para otro feature).
- Re-aperturar una nota `confirmed` o reasignar cliente desde caja
  (mockups exploraron la idea pero quedó out — caja cobra contra lo que
  el vendedor armó; si se equivocó, se cancela y se rehace).
- Permitir cobro parcial de inmediatas (sigue siendo todo-o-nada; si
  cliente quiere pagar parcial, es credit).
- Notificaciones cross-rol (vendedor sabe que caja cobró, etc.).

## Testing

`spec/models/order_spec.rb`:
- Nuevo enum incluye `pending`. Default = `pending`.
- `outstanding_balance` devuelve `total - allocations` para ambos tipos,
  `0` solo si `cancelled`.
- `refresh_status_from_balance!` promueve a `confirmed` cuando balance == 0,
  vuelve a `pending` si vuelve a quedar saldo (no esperado pero defensivo).
- Validación `paper_number` requerido siempre.

`spec/services/sales/create_order_spec.rb`:
- Ya no acepta `payments:` ni `discount_percent:` (parámetros eliminados).
- Crea order `pending` con `total_amount == original_total_amount` y todos
  los items con `discount_percent: 0`.
- Falla si no se provee `paper_number` (incluido para `source: live`).

`spec/services/payments/collect_sale_note_spec.rb` (nuevo):
- Cobro con `discount: 0`, tender único cash, monto exacto → success;
  order pasa a `confirmed`, allocation creada.
- Cobro con `discount: 5`, tender único cash, monto = total*0.95 → success;
  items reciben `discount_percent: 5`; `total_amount` recalculado.
- Cobro con `discount: 5` pero tender `transfer` → `failure`.
- Cobro con `discount: 5`, mix cash + transfer → `failure`.
- Cobro con suma de tenders ≠ total → `failure`.
- Orden `credit` o `confirmed` → `failure` (validación de tipo/estado).

`spec/services/payments/allocate_payment_spec.rb`:
- Allocation que deja `outstanding_balance == 0` → order pasa a
  `confirmed` automáticamente.
- Allocation parcial → order queda `pending`.

`spec/requests/web/sale_notes_spec.rb` (nuevo):
- `GET /web/sale_notes` como caja → 200, lista solo immediate pending.
- Como vendedor → forbidden.

`spec/requests/web/sale_notes/payments_spec.rb` (nuevo):
- `POST` con datos válidos → cobra, redirige al listado.
- `POST` violando regla cash-only → render :new con error.

`spec/policies/order_policy_spec.rb`:
- `cancel_pending?` permite vendedor/caja/admin para orders pending,
  niega para confirmed.

## Implementación sugerida (fases)

Un solo spec, pero la implementación se puede partir en 3 commits:

1. **Modelo + scopes** (`Order` enum, `outstanding_balance` generalizado,
   `Customer#current_balance`, dashboard, receivables filter).
   Incluye la simplificación de `Sales::CreateOrder` y el form del
   vendedor. Después de este commit, todas las notas nacen `pending` y
   las credit funcionan en cobranza existente (`AllocatePayment` con
   auto-promoción a `confirmed`).
2. **Caja flow** (`Payments::CollectSaleNote`, controllers + views +
   Stimulus + policies + sidebar entry).
3. **Cleanup** (corregir `WORKING_CONTEXT.md`, simplificar
   `order_form_controller.js`, borrar `Payments::RegisterPayment` ya
   deprecado si sigue en codebase).

Entre fase 1 y 2 las notas immediate quedan sin UI de cobro (estado
inválido). Implementar 1 y 2 en la misma PR.
