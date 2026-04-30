# Pago parcial en ventas a cuenta corriente — Design Spec

**Fecha:** 2026-04-30
**Branch sugerida:** `feat_04-partial-payment-on-credit-sales`
**Estado:** Aprobado en brainstorming, pendiente plan de implementación

## Contexto

El feature de cuentas corrientes está completo en backend solo en sus piezas separadas:

- `Sales::CreateOrder` crea órdenes `credit` por el total de la venta.
- `Payments::RegisterPayment` permite registrar pagos sueltos atados al cliente (sin relación a orden).
- `Customer#current_balance` calcula saldo agregado: `Σ(orders credit no canceladas).total_amount − Σ(payments).amount`.

Lo que falta:

1. La UI de creación de venta no expone un campo para "monto que el cliente paga al momento". Hoy el toggle es binario *Contado / Cuenta Corriente*; al elegir cuenta corriente, la venta queda 100% como deuda.
2. No existe orquestación que cree atómicamente la `Order` credit y un `Payment` inicial.
3. `Payment` no puede atarse a una `Order` específica, así que aun creando ambos por separado no hay trazabilidad por venta de cuánto se cobró al momento.

## Objetivo

Permitir que en la creación de una venta a cuenta corriente, el operador registre cuánto cobra al momento (`0`, parcial, o total). El monto restante queda como deuda y se refleja en el `current_balance` del cliente. Las ventas Contado no cambian de comportamiento.

## Alcance

**Incluido:**

- Modelo: `Payment.order_id` opcional (nullable).
- Servicio: `Sales::CreateOrder` acepta un parámetro opcional `initial_payment: { amount:, payment_method: }`.
- Servicio: `Sales::CancelOrder` destruye los payments atados a la orden al cancelar.
- UI: Vista de creación de venta muestra dos campos extra ("Monto que paga ahora" + selector de método) cuando el toggle está en Cuenta Corriente.
- UI: Vista de detalle de orden lista los payments asociados (read-only) y muestra el saldo pendiente de la venta.

**Excluido (explícitamente fuera de alcance):**

- Las ventas Contado (`order_type: "immediate"`) **siguen sin generar `Payment`**. El discriminador entre contado y crédito es `order_type`, no la presencia de payments. Si en el futuro se quiere un libro de cobros completo (alcance B descartado en brainstorming), sería un cambio aparte.
- Pagos mixtos (parte efectivo + parte transferencia en una misma venta).
- Sobrepago como saldo a favor del cliente.
- Edición de la venta una vez creada (no se permite hoy y este feature no lo cambia).
- Anulación parcial / "deshacer un cobro" sin cancelar la orden completa.

## Decisiones de diseño

### 1. Modelo de datos: `Payment.order_id` nullable

`Payment` gana una FK opcional a `Order`. Los pagos sueltos al cliente (los que crea `Web::Customers::PaymentsController`) siguen funcionando con `order_id: nil`. Los pagos creados como cobro inicial de una venta llevan `order_id` apuntando a la orden recién creada.

**Por qué esta opción** (vs `Order.amount_paid` o solo saldo agregado):

- Mantiene trazabilidad por orden ("¿cuánto se cobró de la venta del martes?").
- No duplica datos (vs un `Order.amount_paid` que tendría que mantenerse en sync con los Payment).
- La fórmula de `Customer#current_balance` no necesita cambios.
- No rompe el flujo actual de payments sueltos.

### 2. UX: toggle existente + campos condicionales

Se mantiene el toggle binario *💵 Contado / 📋 Cuenta Corriente*. Cuando el usuario elige Cuenta Corriente, aparecen dos campos:

- **"Monto que paga ahora"** — input numérico, default `0`, rango `0 ≤ monto ≤ total_amount`.
- **"Método de pago"** — select con `cash` (default), `transfer`, `check`, `card`.

Cuando vuelve a Contado, ambos campos se ocultan y el monto se resetea a `0`.

**Por qué esta opción** (vs unificar en un solo campo "monto pagado"): cambio incremental, no rompe la mental model del operador, mantiene la lógica del Cliente Mostrador (siempre `immediate`) intacta.

### 3. Reglas del monto pagado

`0 ≤ monto ≤ total_amount`. Validación dura en el servicio:

- `monto < 0` → rechazar.
- `monto > total_amount` → rechazar con mensaje "El monto cobrado no puede exceder el total de la venta ($X)".
- `monto == 0` → tratar como `nil` (no crear `Payment`).
- `monto == total_amount` → permitido. La orden queda como `credit` con un `Payment` por el total. La intención del usuario (toggle Cuenta Corriente) prevalece sobre la conveniencia de auto-convertir a `immediate`.

No se permiten sobrepagos (saldo a favor del cliente).

### 4. Método de pago: selector visible

El método de pago se elige explícitamente en el formulario de venta (default *Efectivo*). Coherente con el formulario de payments sueltos en `Web::Customers::PaymentsController`.

### 5. Cancelación: destruir payments asociados

`Sales::CancelOrder` destruye los `Payment` con `order_id == @order.id` dentro de su transacción. La venta cancelada se "deshace" como si nunca hubiera ocurrido: stock vuelve, deuda desaparece, cobro inicial desaparece.

**Por qué esta opción** (vs mantener el Payment como saldo a favor o agregar `voided_at`): consistente con cómo `CancelOrder` ya restock simétricamente; sin nuevos campos de auditoría que el feature no necesita hoy.

### 6. Servicio: extender `Sales::CreateOrder`

`Sales::CreateOrder` acepta un nuevo parámetro opcional `initial_payment` (default `nil`). Si viene, dentro de la transacción ya existente del servicio, se crea el `Payment` después de crear la orden, items y stock movements.

**Por qué esta opción** (vs orquestador `Sales::CreateOrderWithPayment`): cambio mínimo; el controller sigue llamando un solo servicio; `Sales::CreateOrder` ya maneja la transacción y conoce la orden recién creada; los call sites existentes (specs, seeds) no rompen.

## Cambios técnicos

### Migración

```ruby
class AddOrderToPayments < ActiveRecord::Migration[7.2]
  def change
    add_reference :payments, :order, null: true, foreign_key: true, index: true
  end
end
```

### `Payment` model

```ruby
class Payment < ApplicationRecord
  belongs_to :customer
  belongs_to :order, optional: true   # nuevo

  PAYMENT_METHODS = %w[cash transfer check card].freeze

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :payment_method, presence: true, inclusion: { in: PAYMENT_METHODS }
  validates :payment_date, presence: true
  validate  :customer_must_have_credit_account
  validate  :amount_within_order_total, if: :order   # nuevo

  # ... resto sin cambios

  private

  def amount_within_order_total
    return if amount.nil? || order.total_amount.nil?
    if amount > order.total_amount
      errors.add(:amount, "no puede exceder el total de la orden ($#{order.total_amount})")
    end
  end
end
```

### `Order` model

```ruby
has_many :payments, dependent: :destroy   # nuevo
```

(Solo declara la asociación. No destruimos `Order` desde ningún lado, así que `dependent: :destroy` no tiene efecto secundario hoy. `Sales::CancelOrder` invocará `@order.payments.destroy_all` explícitamente.)

### `Sales::CreateOrder` — diff conceptual

Nueva firma:

```ruby
def self.call(customer:, items:, order_type:, channel: nil, source: "live",
              sale_date: nil, paper_number: nil, initial_payment: nil)
```

Validaciones extra en `validate_params` cuando `@initial_payment` viene con valor:

- `order_type == "credit"` (rechazar si llega con `immediate`).
- `amount.to_f > 0` (si es 0, normalizar a `nil` y no crear payment).
- `amount <= calculate_total` (rechazar sobrepago).
- `payment_method` está en `Payment::PAYMENT_METHODS` cuando viene presente. El parser del controller siempre completa `payment_method` (default `"cash"` si el usuario no eligió), así que el servicio en la práctica nunca recibe nil; la validación protege contra call sites futuros que pasen un valor inválido.

Dentro de la transacción ya existente, después de `create_stock_movements`:

```ruby
create_initial_payment if @initial_payment

# ...

def create_initial_payment
  Payment.create!(
    customer: @customer,
    order: @order,
    amount: @initial_payment[:amount],
    payment_method: @initial_payment[:payment_method],
    payment_date: @sale_date
  )
end
```

`payment_date` se alinea con `@sale_date` para coherencia con ventas `from_paper` (fecha distinta a hoy).

### `Sales::CancelOrder`

Dentro de su transacción, antes (o después) de cambiar `status` a cancelled:

```ruby
@order.payments.destroy_all
```

### `Web::OrdersController#create`

Pasar el nuevo parámetro al servicio:

```ruby
result = Sales::CreateOrder.call(
  customer: find_or_create_customer,
  items: parse_items,
  order_type: params.dig(:order, :order_type) || "immediate",
  channel: params.dig(:order, :channel),
  source: params[:source] || "live",
  sale_date: params[:sale_date],
  paper_number: params[:paper_number],
  initial_payment: parse_initial_payment
)
```

Helper privado:

```ruby
def parse_initial_payment
  return nil unless params.dig(:order, :order_type) == "credit"
  return nil if params[:initial_payment_amount].blank?

  amount = params[:initial_payment_amount].to_f
  return nil if amount <= 0

  {
    amount: amount,
    payment_method: params[:initial_payment_method].presence || "cash"
  }
end
```

El controller solo parsea; toda validación dura es del servicio.

### Vista `app/views/web/orders/new.html.haml`

Dentro del Card 1 (Información del Cliente), después del selector de cliente y antes del canal, agregar un bloque condicional controlado por Stimulus:

```haml
%div{ data: { order_form_target: "creditPaymentSection" }, class: "space-y-3 hidden border-t border-gray-200 pt-4" }
  %h4.text-sm.font-semibold.text-gray-900.mb-3 Cobro al Momento

  %div
    = label_tag :initial_payment_amount, "Monto que paga ahora", class: "block text-sm font-medium text-gray-700 mb-2"
    = number_field_tag :initial_payment_amount, 0,
        step: "0.01", min: "0",
        data: { order_form_target: "initialPaymentInput", action: "input->order-form#updateInitialPayment" },
        class: "w-full px-4 py-3 border border-gray-300 rounded-xl focus:ring-2 focus:ring-gray-700"
    %p.text-xs.text-gray-500.mt-1 Dejá en 0 si el cliente no paga nada al momento

  %div
    = label_tag :initial_payment_method, "Método de pago", class: "block text-sm font-medium text-gray-700 mb-2"
    = select_tag :initial_payment_method,
        options_for_select([["💵 Efectivo", "cash"], ["🏦 Transferencia", "transfer"], ["📄 Cheque", "check"], ["💳 Tarjeta", "card"]], "cash"),
        class: "w-full px-4 py-3 border border-gray-300 rounded-xl"
```

### Stimulus controller `order-form` (extensión)

Nuevas targets: `creditPaymentSection`, `initialPaymentInput`.

Comportamiento:

- En `updateOrderType`: si `credit` → `creditPaymentSection.classList.remove("hidden")`. Si `immediate` → `add("hidden")` y `initialPaymentInput.value = 0`.
- Nuevo `updateInitialPayment` (action `input->order-form#updateInitialPayment`): valida client-side `value <= total`. Si excede, muestra warning visual y deshabilita el submit.
- En el card *Resumen de Venta*, agregar dos líneas calculadas dinámicamente cuando `credit && monto > 0`:
  - "Paga ahora: $X"
  - "Queda debiendo: $(total − monto)" en `text-amber-600`

### Vista `app/views/web/orders/show.html.haml`

Cuando `@order.credit_order_type?`, agregar bloque "Pagos asociados":

- Lista `@order.payments` (cargada en el controller con `includes(:payments)`).
- Por cada payment: monto, método (label en español), fecha, notas si las hay.
- Si no hay payments → mensaje "Sin pagos registrados aún".
- Línea de saldo: "Saldo pendiente de esta venta: $(total − Σ payments)".
- Read-only en este feature; los pagos extra siguen registrándose desde la vista del cliente.

### Tests

**`spec/services/sales/create_order_spec.rb`** — agregar contexto `"with initial_payment"`:

- Crea Order credit + Payment atado en una transacción atómica.
- Acepta `amount == 0` o `nil` y no crea Payment.
- Acepta `amount == total` (caso borde superior).
- Rechaza `order_type: "immediate"` con initial_payment.
- Rechaza `amount > total`.
- Rechaza `payment_method` inválido.
- Si `Payment.create!` falla → rollback completo (orden no queda, stock no se mueve).

**`spec/services/sales/cancel_order_spec.rb`** — agregar:

- Cancelar una orden credit con Payment asociado destruye también el Payment dentro de la misma transacción.

**`spec/models/payment_spec.rb`** — agregar:

- Permite `order_id: nil` (pagos sueltos siguen funcionando).
- Permite `order_id` válido apuntando a una orden credit.
- Rechaza si `amount > order.total_amount`.

**`spec/requests/web/orders_spec.rb`** (crear si no existe) — request spec mínimo:

- POST `/web/orders` con `order_type: "credit"` e `initial_payment_amount: 50` crea Order + Payment con `order_id`.
- POST `/web/orders` con `order_type: "immediate"` e `initial_payment_amount: 50` ignora el monto (parser devuelve nil) y crea solo la Order.

### Actualización de `WORKING_CONTEXT.md`

Reflejar:

- `Sales::CreateOrder` acepta `initial_payment:` opcional para órdenes credit.
- `Payment` puede atarse opcionalmente a `Order` vía `order_id`.
- `Sales::CancelOrder` destruye los payments asociados al cancelar.
- Ajustar la nota *"Customer Payment records are not allocated to specific orders"* — ya no es estrictamente cierto: los pagos sueltos siguen sin order, pero los cobros iniciales de venta sí están atados.

## Validaciones / mensajes de error (en español)

Levantados desde `Sales::CreateOrder` como `ValidationError`:

- `"El cobro al momento solo aplica a ventas a cuenta corriente"` — si `initial_payment` viene con `order_type: "immediate"`.
- `"El monto cobrado no puede exceder el total de la venta ($X)"` — si `amount > total`.
- `"Método de pago inválido"` — si `payment_method` no está en `Payment::PAYMENT_METHODS`.

El controller los renderiza en `flash.now[:alert]` como ya hace hoy.

## Riesgos y consideraciones

- **Compatibilidad de seeds/tests existentes:** `Sales::CreateOrder.call` sin `initial_payment` debe seguir funcionando idéntico. El parámetro tiene default `nil` y la lógica nueva está completamente detrás de un guard `if @initial_payment`.
- **Atomicidad:** la creación del Payment va dentro de la transacción ya existente. Si falla cualquier paso (orden, items, stock movements, payment), rollback completo. Ningún Payment huérfano.
- **`Payment` validates `customer.has_credit_account?`:** ya está, no necesita cambio. Al crear el Payment dentro del servicio, el cliente ya pasó la validación de credit account vía la creación de la orden credit.
- **Cliente Mostrador (retail, sin cuenta corriente):** no puede tener orden credit (validación existente), por lo tanto nunca llegará al flujo de initial_payment. El parser del controller también ignora el monto si `order_type != "credit"`.
- **Stimulus state:** el campo `initial_payment_amount` debe limpiarse a 0 al volver a Contado para evitar que un valor previamente cargado se envíe accidentalmente. El parser del controller también lo descarta si `order_type != "credit"`, así que es defensa en profundidad.
- **`from_paper` orders:** `payment_date = sale_date` mantiene coherencia cuando se carga una venta con fecha pasada.

## Plan de implementación

Pendiente — se desarrolla con la skill `writing-plans` después de la aprobación final del usuario sobre este spec.

## Referencias al código actual

- [app/services/sales/create_order.rb](../../../app/services/sales/create_order.rb)
- [app/services/sales/cancel_order.rb](../../../app/services/sales/cancel_order.rb)
- [app/services/payments/register_payment.rb](../../../app/services/payments/register_payment.rb)
- [app/models/payment.rb](../../../app/models/payment.rb)
- [app/models/order.rb](../../../app/models/order.rb)
- [app/models/customer.rb](../../../app/models/customer.rb)
- [app/controllers/web/orders_controller.rb](../../../app/controllers/web/orders_controller.rb)
- [app/views/web/orders/new.html.haml](../../../app/views/web/orders/new.html.haml)
- [app/views/web/customers/payments/new.html.haml](../../../app/views/web/customers/payments/new.html.haml)
