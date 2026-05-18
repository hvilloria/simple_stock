# Payment Allocation to Orders — Design Spec

**Date:** 2026-05-12
**Feature:** feat_06-payment-allocation

## Context

Hoy el modelo `Payment` ata un cobro a **una sola** orden (`payments.order_id`). En la práctica, un cliente con cuenta corriente suele tener varias ventas a crédito pendientes y entrega un único pago que cubre varias de ellas — total o parcialmente.

Casos reales que no podemos modelar bien hoy:

1. 4 ventas a crédito de $25 c/u ($100 total). El cliente paga $100 en efectivo el viernes y quiere que se aplique a las 4 órdenes.
2. 4 ventas de $25 ($100 total). Trae $50 y elige cuáles dos órdenes se dan por pagas.
3. Mismo cliente entrega $300 en efectivo y $200 por transferencia en una sola visita, distribuidos sobre varias órdenes.

Además, el formulario actual de cobro (`Web::Customers::PaymentsController#new`) crea pagos sueltos (`order_id: nil`) que solo reducen el balance global del cliente — el operador no tiene forma de decir "este pago va a estas órdenes".

Esta feature reemplaza el modelo "un payment por una orden" por **"un payment representa un tender (entrega física de plata con un método), y un payment se asigna a una o varias órdenes vía una tabla `payment_allocations`"**.

---

## Scope

### In scope

1. Nueva tabla `payment_allocations` (join `payments` ↔ `orders` con `amount` por allocation)
2. Modelo `PaymentAllocation` con validaciones
3. Refactor de `Payment`: dropear columna `order_id`, agregar `has_many :allocations`
4. Refactor de `Order#outstanding_balance` para usar `allocations` en lugar de `payments`
5. Refactor de `Sales::CreateOrder` (parámetro `initial_payment`) — crear `Payment` + 1 `Allocation`
6. Refactor de `Sales::CancelOrder` — manejar payments asociados (ver _Known limitations_)
7. Nuevo servicio `Payments::AllocatePayment` (agrupa allocations por método y crea N Payments + sus Allocations en una transacción)
8. Nuevo formulario `web/customers/:id/payments/new` — tabla con todas las órdenes pendientes; checkbox por fila; monto y método de pago por fila; resumen en vivo
9. Refactor de `Web::Customers::PaymentsController#create` para usar el nuevo servicio
10. Empty states del form: (a) cliente sin credit account; (b) cliente con credit account y sin órdenes pendientes
11. Actualización de `customers/show` y `orders/show` para leer pagos vía `allocations`
12. Actualización de `customers/debtors` queries si necesario
13. Actualización de `DEVELOPMENT_GUIDE.md` (línea sobre "Payments are global" obsoleta) y `WORKING_CONTEXT.md`

### Out of scope

- Migración de datos preexistente: no hay payments con `order_id` reales en producción que necesiten backfill significativo. La migración drop column será directa.
- UI para "split tender" como wizard explícito — la agrupación por método se hace en el backend, transparente para el operador.
- Modal con el detalle de productos de cada orden al click en "N productos" — placeholder con `dotted underline` por ahora, feature aparte.
- System specs / browser tests.
- Manejo robusto de cancel-with-payments — diferido (ver _Known limitations_).

---

## Architecture

### Schema migration

```ruby
class CreatePaymentAllocations < ActiveRecord::Migration[7.2]
  def change
    create_table :payment_allocations do |t|
      t.references :payment, null: false, foreign_key: true
      t.references :order,   null: false, foreign_key: true
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.timestamps
    end

    add_index :payment_allocations, [:payment_id, :order_id], unique: true

    remove_index :payments, :order_id if index_exists?(:payments, :order_id)
    remove_column :payments, :order_id, :bigint
  end
end
```

### Model: `PaymentAllocation`

```ruby
class PaymentAllocation < ApplicationRecord
  belongs_to :payment
  belongs_to :order

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validate  :order_belongs_to_payment_customer
  validate  :amount_within_order_outstanding_balance

  private

  def order_belongs_to_payment_customer
    return if payment.nil? || order.nil?
    if order.customer_id != payment.customer_id
      errors.add(:order, "no pertenece al cliente del pago")
    end
  end

  def amount_within_order_outstanding_balance
    return if amount.nil? || order.nil?
    other_paid = PaymentAllocation
                   .where(order_id: order_id)
                   .where.not(id: id)
                   .sum(:amount)
    remaining = order.total_amount - other_paid
    if amount > remaining
      errors.add(:amount, "no puede exceder el saldo pendiente de la orden ($#{remaining})")
    end
  end
end
```

### Model: `Payment` (cambios)

- `belongs_to :order, optional: true` → **borrar**
- Agregar `has_many :allocations, class_name: "PaymentAllocation", dependent: :destroy`
- Agregar `has_many :orders, through: :allocations`
- Borrar validación `amount_within_order_total` (ya no aplica — el chequeo vive en `PaymentAllocation`)
- Agregar validación `amount_equals_sum_of_allocations` que corre en `after_validation` o como check post-asignación; en la práctica, el servicio garantiza esto.

### Model: `Order` (cambios)

```ruby
has_many :payment_allocations, dependent: :destroy
has_many :payments, through: :payment_allocations

def outstanding_balance
  return 0 unless credit_order_type?
  return 0 if cancelled_status?
  total_amount - payment_allocations.sum(:amount)
end
```

`Customer#current_balance` queda igual: suma `total_amount` de credit orders confirmadas y le resta `payments.sum(:amount)`. El cálculo no depende de allocations; sigue siendo correcto porque los `Payment` siguen siendo del cliente.

### Service: `Payments::AllocatePayment`

```ruby
Payments::AllocatePayment.call(
  customer: customer,
  payment_date: Date.today,
  notes: "Pago semanal",
  allocations: [
    { order_id: 241, amount: 300, payment_method: "cash" },
    { order_id: 248, amount: 200, payment_method: "transfer" }
  ]
)
```

**Responsabilidades:**

1. Validar `customer.has_credit_account?`
2. Validar `allocations.present?` y cada fila tiene `order_id`, `amount > 0`, `payment_method ∈ Payment::PAYMENT_METHODS`
3. Validar que cada `order` pertenezca al customer, sea `credit`, esté `confirmed`, y `amount <= order.outstanding_balance`
4. **Agrupar por `payment_method`** → para cada grupo, crear un `Payment(amount: sum, method: X)` y sus `PaymentAllocation`s
5. Todo dentro de `ActiveRecord::Base.transaction` — un fallo revierte todo
6. Retornar `Result` con `record: [payments_creados]` o errores

### Service: `Sales::CreateOrder` (cambios)

Si recibe `initial_payment: { amount:, payment_method: }`:

- Crear `Payment(customer: order.customer, amount:, payment_method:, payment_date: order.sale_date)`
- Crear `PaymentAllocation(payment:, order:, amount:)`
- Todo dentro de la misma transacción de creación de orden

### Service: `Sales::CancelOrder` (cambios)

**Diferido a iteración futura — ver _Known limitations_.** Por ahora, mantener el comportamiento actual (que destruye `@order.payments` via `dependent: :destroy`), reemplazándolo por destruir solo las `PaymentAllocation` de la orden cancelada. Los `Payment` quedan vivos como "cobros sin asignar" — y el `current_balance` del cliente automáticamente los descuenta.

```ruby
@order.payment_allocations.destroy_all
# Payments quedan vivos: bajan el current_balance del cliente
# pero ya no se aplican a esta orden cancelada (que tampoco suma deuda).
```

### Controller: `Web::Customers::PaymentsController`

`#new`:
```ruby
def new
  authorize Payment.new(customer: @customer), :new?
  @pending_orders = @customer.orders
                              .credit
                              .where(status: "confirmed")
                              .includes(:payment_allocations)
                              .select { |o| o.outstanding_balance > 0 }
                              .sort_by(&:created_at)
end
```

`#create`:
```ruby
def create
  authorize Payment.new(customer: @customer), :new?
  result = Payments::AllocatePayment.call(
    customer: @customer,
    payment_date: params[:payment_date],
    notes: params[:notes],
    allocations: parsed_allocations
  )

  if result.success?
    redirect_to web_customer_path(@customer), notice: "Cobro registrado: #{ ... }"
  else
    @pending_orders = ... # rehidratar
    flash.now[:alert] = result.errors.join(", ")
    render :new, status: :unprocessable_entity
  end
end

private

def parsed_allocations
  Array(params[:allocations]).reject { |row| row[:amount].blank? || row[:amount].to_f <= 0 }
                              .map { |row| row.permit(:order_id, :amount, :payment_method).to_h.symbolize_keys }
end
```

Sigue thin: parsea params → llama service → redirige.

---

## UI

### Form `web/customers/:id/payments/new`

Layout final aprobado en brainstorming (`payment-form-v4.html`). Resumen:

**Header claro:** título "Registrar Cobro" en slate-900, nombre del cliente en subtítulo slate-500. Link back con `←`.

**Card resumen (4 stats):** Deuda total / Cobrando ahora / Saldo restante / Órdenes incluidas. Border slate-200, white bg, divisores con border-left. Los números actualizan en vivo vía Stimulus controller mientras el operador edita.

**Card tabla de órdenes:** columnas `[☐] Factura · Fecha · Ítems · Total · Cobrado · Pendiente · Cobrar · Método`. Tildar la fila habilita los inputs y autopopula `Cobrar` con `outstanding_balance` (editable). Destildar la deshabilita y limpia. "N productos" es un link con `dotted underline` (placeholder para modal futuro).

**Card footer:** Fecha del cobro · Notas (opcional) · botón "Cancelar" (secondary slate) · botón "Registrar Cobro" (primary slate-700).

**Empty states (en lugar de la tabla):**

| Caso | Mensaje | CTA |
|---|---|---|
| Cliente sin credit account | "Este cliente no tiene cuenta corriente habilitada." | "← Volver" + "Editar cliente" |
| Con credit account, sin órdenes pendientes | "Este cliente no tiene órdenes con saldo pendiente. Está al día." | "← Volver al cliente" |

Estilos consistentes con `customers/debtors` (icon en círculo + título + descripción).

### Navegación

- **Entrada:** botón "Registrar Pago" en `customers/show` (existente) y "+ Pago" por fila en `customers/debtors` (existente). Ambas URLs apuntan a `new_web_customer_payment_path(@customer)`.
- **Submit exitoso →** redirect a `web_customer_path(@customer)` con flash `notice` ("Cobro de $X registrado sobre N órdenes"). El operador ve el saldo actualizado.
- **Cancel / botón ←** → `redirect_back fallback_location: web_customer_path(@customer)` — vuelve al origen (debtors o show).

### Comportamiento del form (Stimulus)

Un controller liviano (`payment_allocation_controller.js`) que:

- Al tildar checkbox: habilita `amount` input + `payment_method` select, setea `amount = pending` (del data-attribute), saca opacity de la fila
- Al destildar: deshabilita inputs, limpia valores, agrega opacity
- En cualquier cambio de inputs: recalcula `cobrando_ahora`, `saldo_restante`, `ordenes_incluidas` y los inserta en la card resumen
- Submit: si `cobrando_ahora == 0`, deshabilita el botón con tooltip "Tildá al menos una orden"

Sin AJAX, sin Turbo Frames — el submit es un POST normal.

---

## Validaciones / reglas de negocio

1. **Cliente debe tener credit account.** Validado en `Payment` (existente) y reforzado en `Payments::AllocatePayment`.
2. **`amount > 0`** por allocation. Validado en `PaymentAllocation` y en el form (HTML5 `min="0.01"`).
3. **No se puede sobrepagar una orden.** `PaymentAllocation#amount_within_order_outstanding_balance` excluye la allocation actual (mismo patrón que el fix de feat_05 con `where.not(id: id)`).
4. **Cada orden de la allocation debe pertenecer al customer, ser `credit`, estar `confirmed`.**
5. **Una misma orden no puede aparecer dos veces en el mismo `Payment`** — enforced via unique index `(payment_id, order_id)`.
6. **`payments.amount == SUM(allocations.amount WHERE payment_id = X)`** — invariante garantizada por el servicio (no validación de modelo, porque el orden de creación dentro de la transacción lo hace tautológico).

---

## Testing

### `spec/models/payment_allocation_spec.rb` (nuevo)

```
validations
  - is invalid without amount
  - is invalid with amount <= 0
  - is invalid when order belongs to a different customer
  - is invalid when amount exceeds order outstanding balance
  - is valid when amount equals exactly the remaining balance
  - is valid when amount is partial within remaining balance
  - excludes itself on update (where.not(id: id))
```

### `spec/models/payment_spec.rb` (refactor)

- Borrar tests de `amount_within_order_total` (la lógica migra a allocation)
- Borrar tests que asumen `payment.order_id`
- Agregar tests para `has_many :allocations, :orders through:`

### `spec/models/order_spec.rb` (refactor)

- Actualizar tests de `outstanding_balance` para crear `Payment + Allocation` en lugar de `Payment(order_id: ...)`

### `spec/services/payments/allocate_payment_spec.rb` (nuevo)

```
.call
  - returns failure when customer has no credit account
  - returns failure when allocations is empty
  - returns failure when an order does not belong to the customer
  - returns failure when an order is not credit or not confirmed
  - returns failure when amount exceeds outstanding balance
  - creates one Payment per payment_method group
  - creates allocations correctly grouped under their Payment
  - sums of allocations match each Payment.amount
  - rolls back everything when any allocation fails
  - on success, Result.record is the array of created Payments
```

### `spec/services/sales/create_order_spec.rb` (extender)

- Cuando se pasa `initial_payment`, crea 1 `Payment` + 1 `PaymentAllocation`
- Mantener tests existentes de orden + items

### `spec/requests/web/customers/payments_spec.rb` (nuevo o extender)

```
GET /web/customers/:id/payments/new
  - 200 when customer has pending credit orders
  - shows empty state when no credit account
  - shows empty state when no pending orders

POST /web/customers/:id/payments
  - creates Payment + Allocations on valid input (single method)
  - creates 2 Payments grouped by method on mixed-method input
  - redirects to customer show with flash on success
  - re-renders new with errors on validation failure
  - rejects allocations summing more than total debt
```

---

## Known limitations

### Cancelación de orden con pagos asignados

Cuando se cancela una orden que ya tiene `PaymentAllocation`s, hoy se borran las allocations (`@order.payment_allocations.destroy_all`). Los `Payment` quedan vivos sin allocations.

Esto deja:
- El cliente con `current_balance` correcto (los Payments siguen restando)
- Pero "Payments huérfanos" que no se ven en ninguna orden y no son fáciles de localizar desde la UI

**Iteración futura propuesta:**

- Vista de Payment individual (`/web/payments/:id/show`) donde se ven sus allocations
- Capacidad de **reasignar** un Payment huérfano a otras órdenes desde esa vista
- Capacidad de eliminar manualmente un Payment huérfano (registrando reason)

Por ahora, lo aceptamos. No hay automatización mágica.

### Sin migración de datos legacy

Si en producción existieran `Payment` records con `order_id` antes del feature, se perderían al dropear la columna. **Asumimos que no es el caso** (confirmado con el equipo: hoy los pagos en producción no se atan a órdenes). Si surge un caso real, se hace un backfill ad-hoc antes del deploy.

### Sin modal de detalle de productos por orden

El link "N productos" en la tabla está como placeholder con `dotted underline`. Abrir un modal con el detalle es una mejora aparte.

---

## Files to modify / create

**Create:**

- `db/migrate/YYYYMMDDHHMMSS_create_payment_allocations.rb`
- `app/models/payment_allocation.rb`
- `app/services/payments/allocate_payment.rb`
- `app/javascript/controllers/payment_allocation_controller.js` (Stimulus)
- `spec/models/payment_allocation_spec.rb`
- `spec/services/payments/allocate_payment_spec.rb`

**Modify:**

- `app/models/payment.rb` — quitar `belongs_to :order` + validación, agregar `has_many :allocations`
- `app/models/order.rb` — `outstanding_balance` desde `payment_allocations`; agregar `has_many :payment_allocations, has_many :payments, through:`
- `app/services/sales/create_order.rb` — `initial_payment` ahora crea Payment + Allocation
- `app/services/sales/cancel_order.rb` — destroy allocations en lugar de payments
- `app/controllers/web/customers/payments_controller.rb` — usar `Payments::AllocatePayment`
- `app/views/web/customers/payments/new.html.haml` — reescribir con la tabla multi-orden
- `app/views/web/customers/show.html.haml` — confirmar que las queries leen vía allocations
- `app/views/web/orders/show.html.haml` — la sección "Pagos de esta Venta" lee `@order.payment_allocations`
- `config/routes.rb` — sin cambios (la ruta ya existe)
- `spec/models/payment_spec.rb`, `spec/models/order_spec.rb`, `spec/services/sales/create_order_spec.rb`
- `spec/requests/web/customers_spec.rb` (si existe; sino crear) o `spec/requests/web/customers/payments_spec.rb`
- `WORKING_CONTEXT.md` — reflejar nuevo modelo `PaymentAllocation`, servicio, y cambios en `Order#outstanding_balance`
- `docs/DEVELOPMENT_GUIDE.md` — actualizar la sección "Payments" (línea 137-141): los pagos ahora pueden ser globales **o** asignados a una o más órdenes vía allocations.

---

## Open questions

Ninguna pendiente al momento de cerrar el spec. Decisiones tomadas:

- Cancel-with-payments → known limitation, futura iteración
- Backfill → no necesario
- Drop `payments.order_id` → sí, en la migración
- Método de pago por fila (UI), agrupado por método (backend) → confirmado
- Empty states → para `no credit account` y `no pending orders`
- Redirect post-éxito → `customer/show`; cancel → `redirect_back`
