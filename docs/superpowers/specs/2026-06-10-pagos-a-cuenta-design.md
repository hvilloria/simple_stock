# feat_11 — Pagos a cuenta (`on_account`)

## Objetivo

Hoy una venta (`Order`) solo puede ser **inmediata** (`immediate`, caja cobra el
total) o **a crédito** (`credit`, deuda de un cliente con cuenta corriente). En el
mostrador existe un tercer caso que el sistema no representa: el **pago a cuenta**,
donde el cliente **paga una parte ahora y el resto después**, y la mercadería se
**entrega de forma progresiva**. La operación queda **abierta** hasta que el cliente
termina de pagar **y** retira todo lo comprado.

No es inmediata (queda saldo) ni es a crédito (cliente de mostrador, sin cuenta
corriente; la plata es efectivo entregado contra mercadería, no una deuda a favor del
local). Por eso es su propio tipo de venta (`order_type: "on_account"`), con su propio
espacio en la app.

> La fuente de la necesidad de negocio es `PAGOS_A_CUENTA_FEATURE.md`. Este documento
> agrega las decisiones técnicas tomadas durante el brainstorming.

## Reglas del negocio

1. **Nuevo `order_type: "on_account"`.** No reusa `credit` ni un flag — bucket limpio.
   Nace `pending`; promueve a `confirmed` cuando el saldo llega a 0 vía el ya existente
   `Order#refresh_status_from_balance!`.
2. **No es deuda de cuenta corriente.** No requiere `customer.has_credit_account?` y
   **no** entra en `Customer#current_balance` (la fórmula solo filtra `order_type:
   "credit"`, así que `on_account` queda fuera sin tocar nada).
3. **Contacto obligatorio (solo este tipo).** Nombre + teléfono de texto libre, guardados
   en la orden. El cliente asociado queda como Mostrador. Permite ubicar y llamar al
   cliente cuando llega el repuesto faltante.
4. **Pago y entrega son ejes independientes.** Se puede cobrar por adelantado sin
   entregar (la seña) y entregar antes de saldar.
5. **Liquidada (sale de la lista de abiertas):** saldo = 0 **y** todos los ítems
   entregados. Una operación pagada pero sin retirar (entrega 0/2, saldo $0) **sigue
   apareciendo** hasta entregar.
6. **Cobro parcial y repetible.** Cada visita CAJA cobra una parte del saldo. Guard duro:
   el monto a cancelar nunca puede superar el saldo pendiente.
7. **Descuento por evento, cash-only.** En cada cobro se ofrece 0/5/10% sobre el monto
   que se cancela en esa visita, válido **solo si todos los tenders de ese cobro son
   efectivo** (regla análoga a `CollectSaleNote`, acotada al evento). El descuento lo
   absorbe el local: **baja `total_amount`**, no la deuda.
8. **Entrega la define el vendedor**, no CAJA. En la pantalla de cobro es solo lectura.
9. **Stock:** sin cambios. Marcar entregado **no** genera `StockMovement` todavía (hoy
   ninguna venta mueve stock). Queda fuera de alcance (ver abajo).

## Modelo de datos

### Migración 1 — contacto en `orders`

```ruby
# db/migrate/XXXX_add_contact_to_orders.rb
class AddContactToOrders < ActiveRecord::Migration[7.2]
  def change
    add_column :orders, :contact_name,  :string
    add_column :orders, :contact_phone, :string
  end
end
```

Nullable en BD (las órdenes `immediate`/`credit` no los usan). La obligatoriedad para
`on_account` se fuerza a nivel de modelo.

### Migración 2 — entrega por ítem en `order_items`

```ruby
# db/migrate/XXXX_add_delivered_at_to_order_items.rb
class AddDeliveredAtToOrderItems < ActiveRecord::Migration[7.2]
  def change
    add_column :order_items, :delivered_at, :datetime
  end
end
```

`NULL` = no entregado. No hay backfill (sin órdenes productivas).

El `order_type` **no** necesita migración: es una columna `string` y el valor nuevo se
agrega solo al enum del modelo.

### Cambios en `Order`

```ruby
enum :order_type, {
  immediate:  "immediate",
  credit:     "credit",
  on_account: "on_account"
}, suffix: true

scope :on_account, -> { where(order_type: "on_account") }

# Open = aún debe plata O aún quedan ítems sin entregar (= no liquidada).
# El saldo depende de allocations; ambas condiciones en un solo HAVING (Postgres).
scope :open_on_account, -> {
  on_account.active
    .left_joins(:order_items)
    .group("orders.id")
    .having(
      "orders.total_amount - " \
      "COALESCE((SELECT SUM(amount) FROM payment_allocations WHERE order_id = orders.id), 0) > 0 " \
      "OR COUNT(*) FILTER (WHERE order_items.delivered_at IS NULL) > 0"
    )
}

# Búsqueda por contacto para la pantalla de CAJA / vendedor.
scope :search_contact, ->(q) {
  return all if q.blank?
  where("contact_name ILIKE :q OR contact_phone ILIKE :q", q: "%#{q.strip}%")
}

validate :on_account_requires_contact

def fully_delivered?
  order_items.where(delivered_at: nil).none?
end

# Liquidada: pagada y entregada por completo.
def settled?
  outstanding_balance <= 0 && fully_delivered?
end

def delivered_items_count
  order_items.where.not(delivered_at: nil).count
end

private

def on_account_requires_contact
  return unless on_account_order_type?
  errors.add(:contact_name,  "es obligatorio para pagos a cuenta") if contact_name.blank?
  errors.add(:contact_phone, "es obligatorio para pagos a cuenta") if contact_phone.blank?
end
```

`outstanding_balance` y `refresh_status_from_balance!` ya existen y sirven sin cambios
(`total_amount - Σ allocations`; promueve a `confirmed` al llegar a 0).

`Customer#current_balance` **no se toca**: ya filtra `order_type: "credit"`, así que
`on_account` queda naturalmente excluido de la deuda de cuenta corriente.

### Decisión de modelado — atributos por tipo

Los campos de contacto viven como columnas nullable en `orders` con validación
condicional (`on_account_requires_contact`), no en una tabla aparte. Es consistente con
el patrón ya existente (`credit_order_requires_credit_account`, validaciones según
`from_paper?`), evita un join y una entidad de primera clase que justamente **no**
queremos crear (el contacto es descartable; no abre cuenta corriente ni `Customer`).
**Umbral para extraer a tabla propia:** si el contacto creciera (dirección, email,
documento) o aparecieran varios tipos con su propia bolsa de campos → `delegated_type` /
STI. Hoy son 2 strings; no estamos cerca.

`delivered_at` **no** es específico de `on_account`: la entrega es general (una venta
`immediate` se entrega toda en el momento). `on_account` solo la vuelve progresiva. Por
eso vive en `order_items` como columna general, lista para el futuro refactor de stock al
entregar (ver Out of scope).

## Capa de servicio

### `Payments::CollectOnAccount` — nuevo (cobro parcial repetible)

Servicio hermano de `CollectSaleNote`, no una extensión: las reglas difieren de forma
material (parcial vs total exacto; descuento por evento que baja `total_amount` vs
descuento global per-item; repetible vs one-shot). Mantener `CollectSaleNote` con una
sola responsabilidad es consistente con `AGENTS.md`.

```ruby
Payments::CollectOnAccount.call(
  order:,                  # Order — debe ser on_account + activa (no cancelada)
  amount_to_settle:,       # cuánto del saldo cancela en esta visita (> 0, ≤ saldo)
  discount_percent: 0,     # 0, 5 o 10 — descuento de ESTE cobro
  tenders: [               # multi-fila método+monto; suma == efectivo a cobrar
    { payment_method: "cash", amount: 45_000 }
  ],
  payment_date: Date.current
)
```

Reglas en orden:

1. Validar `order.on_account_order_type?` y `!order.cancelled_status?`.
2. Validar `discount_percent ∈ {0, 5, 10}`.
3. Validar `amount_to_settle > 0` y `amount_to_settle ≤ order.outstanding_balance`
   (guard duro: nunca se cobra de más).
4. Validar cada tender (`payment_method ∈ PAYMENT_METHODS`, `amount > 0`).
5. Calcular el efectivo a cobrar:

   ```ruby
   discount_value  = (amount_to_settle.to_d * discount_percent / 100).round(2)
   cash_to_collect = amount_to_settle.to_d - discount_value
   ```

6. **Regla cash-only:** si `discount_percent > 0`, todos los tenders deben ser `cash`.
   En cualquier caso `SUM(tenders.amount) == cash_to_collect` (tolerancia 0.01).
7. Transacción:
   - Si `discount_value > 0`: `order.update!(total_amount: order.total_amount -
     discount_value)`. **No** toca `order_items.discount_percent` (es descuento por
     evento, no global per-producto); `original_total_amount` queda intacto, de modo que
     `discount_amount = original − total` refleja el descuento **agregado**.
   - Crear `Payment` + `PaymentAllocation` por el **efectivo real** (`cash_to_collect`),
     agrupando tenders por método (igual que `CollectSaleNote`).
   - `order.refresh_status_from_balance!`.
8. `Result.new(success?: true, record: order, errors: [])`.

**Por qué el saldo baja exactamente `amount_to_settle`:** `saldo' = (total −
discount_value) − (Σ + cash_to_collect) = (total − Σ) − amount_to_settle`. El descuento
se cancela con la rebaja de `total_amount`.

**Ejemplo** (operación $100.000, cancela $50.000 con 10% efectivo): `discount_value =
$5.000`, `cash_to_collect = $45.000`. `total_amount` baja a $95.000, allocation =
$45.000, saldo = $50.000. Segundo cobro de $50.000 sin descuento → saldo $0.

El **aviso suave** (saldo $0 con ítems sin entregar) vive en el controlador/UI, no en el
servicio: el servicio cobra; la confirmación es de presentación.

### `Inventory::MarkDelivered` — nuevo (marca de entrega)

```ruby
Inventory::MarkDelivered.call(
  order:,            # Order on_account
  order_item_ids:,   # ids de order_items a marcar
  delivered: true    # true = entregar (set delivered_at), false = revertir (nil)
)
```

1. Validar `order.on_account_order_type?`.
2. Solo opera sobre `order.order_items` cuyos ids estén en `order_item_ids` (no permite
   tocar ítems de otra orden).
3. `update_all(delivered_at: delivered ? Time.current : nil)` dentro de transacción.
4. **No genera `StockMovement`** (ver Out of scope).
5. `Result.new(success?: true, record: order, errors: [])`.

### `Sales::CreateOrder` — acepta el tipo nuevo

- Acepta `order_type: "on_account"`.
- Recibe y persiste `contact_name:` / `contact_phone:` (requeridos para este tipo; la
  validación de modelo los exige).
- Recibe `delivered_item_indexes:` (o equivalente) para setear `delivered_at:
  Time.current` en los ítems que el cliente se lleva al crear (entrega inicial).
- Estado inicial `pending`, `total_amount == original_total_amount` (sin descuento al
  crear; el descuento es por evento de cobro).

## Capa de controlador

### Rutas (`config/routes.rb`, namespace `web`)

```ruby
resources :payments_on_account, only: [:index, :show] do
  resource :payment, only: [:new, :create],
                     controller: "payments_on_account/payments"
  member do
    post :deliver
  end
end
```

URLs:
- `GET  /web/payments_on_account` → lista de operaciones abiertas (búsqueda nombre/tel).
- `GET  /web/payments_on_account/:id` → detalle (vista vendedor).
- `POST /web/payments_on_account/:id/deliver` → `Inventory::MarkDelivered`.
- `GET  /web/payments_on_account/:id/payment/new` → form de cobro (CAJA).
- `POST /web/payments_on_account/:id/payment` → `Payments::CollectOnAccount`.

### `Web::PaymentsOnAccountController`

```ruby
class Web::PaymentsOnAccountController < Web::ApplicationController
  def index
    authorize Order, :index_on_account?
    @operations = Order.open_on_account
                       .search_contact(params[:q])
                       .order(created_at: :asc)
  end

  def show
    @order = Order.on_account.find(params[:id])
    authorize @order, :show_on_account?
  end

  # vendedor marca/desmarca entrega
  def deliver
    @order = Order.on_account.find(params[:id])
    authorize @order, :deliver?

    result = Inventory::MarkDelivered.call(
      order:          @order,
      order_item_ids: Array(params[:order_item_ids]),
      delivered:      true
    )

    if result.success?
      redirect_to web_payments_on_account_path(@order), notice: "Entrega registrada"
    else
      redirect_to web_payments_on_account_path(@order), alert: result.errors.join(", ")
    end
  end
end
```

### `Web::PaymentsOnAccount::PaymentsController` (CAJA)

```ruby
class Web::PaymentsOnAccount::PaymentsController < Web::ApplicationController
  before_action :set_order

  def new
    authorize @order, :collect?
  end

  def create
    authorize @order, :collect?

    result = Payments::CollectOnAccount.call(
      order:            @order,
      amount_to_settle: parsed_amount(params[:amount_to_settle]),
      discount_percent: params[:discount_percent].to_i,
      tenders:          parsed_tenders
    )

    if result.success?
      redirect_to web_payments_on_account_path(@order), notice: "Cobro registrado"
    else
      flash.now[:alert] = result.errors.join(", ")
      render :new, status: :unprocessable_entity
    end
  end

  private

  def set_order
    @order = Order.on_account.find(params[:payments_on_account_id])
  end

  def parsed_amount(raw)
    raw.to_s.gsub(".", "").gsub(",", ".").to_f
  end

  def parsed_tenders
    Array(params[:tenders]).map do |_, row|
      { payment_method: row[:payment_method], amount: parsed_amount(row[:amount]) }
    end.reject { |t| t[:amount] <= 0 }
  end
end
```

### Policies (`OrderPolicy` o `PaymentOnAccountPolicy`)

```ruby
# Ver lista / detalle: vendedor, caja, admin
def index_on_account? = user.vendedor? || user.caja? || user.admin?
def show_on_account?  = index_on_account?

# Marcar entrega: vendedor, admin
def deliver? = (user.vendedor? || user.admin?) && record.on_account_order_type?

# Cobrar: caja, admin
def collect? = (user.caja? || user.admin?) &&
               record.on_account_order_type? && !record.cancelled_status?
```

## Capa UI

Mockups validados en sesión de brainstorming guardados en `.superpowers/brainstorm/`.
Lenguaje visual sobrio de `docs/UI_DESIGN_SPEC.md` (slate-50, cards blancas `rounded-2xl`
`border-slate-200`, primario slate-900, rojo solo logo/destructivo).

### Pantalla 1 — Lista (`payments_on_account/index.html.haml`)

- Título "Pagos a cuenta", subtítulo "Operaciones abiertas — pendientes de pago o
  entrega".
- **Búsqueda por nombre o teléfono** (`params[:q]`, GET, submit on change/enter).
- Card con tabla: Cliente · Teléfono · Talonario · Total · Pagado · Saldo · Entrega
  (N/M) · acción "Ver →".
- Una operación pagada pero sin retirar sigue apareciendo hasta entregar.

### Pantalla 2 — Detalle / vendedor (`payments_on_account/show.html.haml`)

- Encabezado: talonario + contacto (nombre/teléfono).
- Card **Productos y entrega**: por ítem, checkbox "entregado" (editable solo vendedor);
  los ya entregados muestran ✓ + fecha. Botón "Guardar entrega" → `POST .../deliver`.
- Card **Historial de cobros** (fecha · método · monto).
- Card **Resumen**: total acordado · pagado · saldo · progreso de entrega (N/M).
- Botón **"Cobrar →"**: atajo a `payment/new` de esa operación. **No** mueve la orden a
  "Notas de pedido"; los pagos a cuenta se cobran dentro de su sección.

### Pantalla 3 — Cobro / CAJA (`payments_on_account/payments/new.html.haml`)

Reutiliza el layout del cobro de notas (2 columnas 1fr/360px). Bloques nuevos en amarillo
"nuevo":

- **Izq:**
  - "Productos" read-only, con la entrega visible **solo lectura**.
  - **"Monto a cancelar ahora"** (Variante A): CAJA tipea cuánto del saldo cancela; el
    sistema calcula el efectivo a cobrar (`monto × (1 − desc)`).
  - "Descuento": dropdown 0/5/10%, deshabilitado si no se cumple cash-only.
  - "Detalle de pago": filas método+monto (currency-input AR), "+ Agregar método". La
    suma debe igualar el efectivo a cobrar.
- **Der (sticky):** Total acordado · Ya cobrado · Saldo actual · Cancela ahora ·
  Descuento · A cobrar · Saldo después. Botón "Registrar cobro".
- **Aviso suave:** si el cobro deja saldo $0 con ítems sin entregar, `confirm` JS antes
  del POST ("queda pagada pero faltan N por entregar, ¿confirmar?"). No bloquea.

### Creación — `web/orders/new.html.haml`

- Tercer radio **"Pago a cuenta"** junto a Contado y Cuenta Corriente.
- Campos de **contacto** (nombre + teléfono, requeridos para este tipo) que aparecen al
  elegir el radio.
- **Marcación de entrega inicial** por ítem (checkbox "se lo lleva ahora").
- `order_form_controller.js`: mostrar/ocultar contacto según `order_type`.

### Sidebar

Entrada **"Pagos a cuenta"** con badge de `Order.open_on_account.count` (patrón del
badge de "Notas de pedido"). Visible para vendedor, caja y admin.

## Out of scope

- **`StockMovement` al entregar.** Hoy la entrega es solo una marca. A futuro debería
  generar el movimiento de stock real, atado a un refactor transversal: reemplazar el
  concepto `source` (`live`/`from_paper`) por una noción explícita de "¿este flujo toca
  stock?" (constante tipo `TRACK_STOCK`), dado que todas las ventas tienen talonario y
  hoy ninguna mueve stock. **PR separado.**
- **Devolución / manejo de la seña al cancelar.** Si se cancela una operación con cobros
  ya registrados (plata real entregada), falta definir la devolución. Hoy
  `Sales::CancelOrder` borra las `PaymentAllocation` pero los `Payment` quedan vivos
  (limitación conocida). A resolver pronto, **fuera de este feature**.
- Desglose por evento del descuento (se guarda solo el agregado en `total_amount`).

## Testing

`spec/models/order_spec.rb`:
- Enum `order_type` incluye `on_account`.
- `on_account_requires_contact`: inválida sin `contact_name`/`contact_phone`; válidas para
  `immediate`/`credit` sin contacto.
- `fully_delivered?` / `settled?`: settled solo con saldo 0 **y** todos los ítems con
  `delivered_at`.
- `open_on_account` scope: incluye órdenes con saldo > 0; incluye saldo 0 con ítems sin
  entregar; excluye liquidadas y canceladas.
- `current_balance` de un customer **no** cuenta órdenes `on_account`.

`spec/services/payments/collect_on_account_spec.rb` (nuevo):
- Cobro parcial cash, sin descuento → allocation = monto; saldo baja exacto; sigue
  `pending`.
- Cobro con 10% cash → `total_amount` baja `monto*0.10`; allocation = `monto*0.90`; saldo
  baja `monto`.
- `amount_to_settle > outstanding_balance` → `failure` (guard duro).
- `discount > 0` con tender no-cash → `failure`.
- Suma de tenders ≠ efectivo a cobrar → `failure`.
- Último cobro lleva saldo a 0 → order pasa a `confirmed`.
- Order `immediate`/`credit` o cancelada → `failure`.

`spec/services/inventory/mark_delivered_spec.rb` (nuevo):
- Marca `delivered_at` de los ítems indicados; `delivered: false` lo revierte a `nil`.
- No crea `StockMovement`.
- Ignora ids que no pertenecen a la orden.

`spec/services/sales/create_order_spec.rb`:
- Crea order `on_account` con contacto y entrega inicial (`delivered_at` seteado en los
  ítems llevados).
- Falla sin contacto.

`spec/requests/web/payments_on_account_spec.rb` (nuevo):
- `index`/`show` permitidos a vendedor/caja/admin; `deliver` solo vendedor/admin;
  `payment#create` solo caja/admin.
- `index` lista solo operaciones abiertas y filtra por `q` (nombre/teléfono).

`spec/system/web/payments_on_account_spec.rb` (nuevo):
- Flujo completo: lista → detalle → marcar entrega → cobro, incluyendo el aviso suave al
  saldar con entregas pendientes.

## Implementación sugerida (fases, una sola PR)

1. **Modelo + migraciones** (`order_type` enum, contacto, `delivered_at`, scopes,
   validación, `settled?`/`fully_delivered?`) + `Sales::CreateOrder` y el radio + contacto
   + entrega inicial en `web/orders/new`.
2. **Servicios + CAJA/vendedor** (`Payments::CollectOnAccount`, `Inventory::MarkDelivered`,
   controllers, vistas index/show/payment, Stimulus de cobro reusado, policies, sidebar).
3. **Cleanup** (badge del sidebar, ajustes de copy, system spec).

## Decisiones clave (registro)

- Tipo nuevo `on_account` en inglés (no reusar `credit` ni un flag) — bucket limpio.
- Contacto obligatorio nombre + teléfono, texto libre en la orden.
- Entrega por ítem (`delivered_at`), marcada por el vendedor (creación + detalle).
- Cobro parcial repetible vía servicio hermano `CollectOnAccount`; **Variante A** (CAJA
  tipea el monto del saldo a cancelar).
- Descuento por evento, cash-only, agregado (baja `total_amount`, sin desglose).
- Sin estado "listo para cobrar"; CAJA ubica por búsqueda nombre/teléfono.
- Guard duro `amount_to_settle ≤ saldo` + aviso suave al saldar con entregas pendientes.
