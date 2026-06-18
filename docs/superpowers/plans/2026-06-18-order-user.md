# Order#user (Vendedor) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Registrar el usuario (`User`) que realizó cada venta en `Order#user`, asignándolo desde `current_user` en el controller y mostrándolo en la vista de detalle de la orden.

**Architecture:** Se agrega `user_id NOT NULL` a la tabla `orders` con FK a `users` (on_delete: :restrict). El servicio `Sales::CreateOrder` recibe `user:` como parámetro obligatorio y lo pasa a `Order.create!`. El controller web pasa `current_user`. La vista show ya tiene el bloque "Registrado por" con el texto hardcodeado "Sistema" — se reemplaza con `@order.user.name`.

**Tech Stack:** Rails 7.2, PostgreSQL, RSpec, FactoryBot, HAML

---

## Mapa de archivos

| Acción   | Archivo |
|----------|---------|
| Crear    | `db/migrate/TIMESTAMP_add_user_to_orders.rb` |
| Modificar | `app/models/order.rb` |
| Modificar | `spec/factories/orders.rb` |
| Modificar | `app/services/sales/create_order.rb` |
| Modificar | `spec/services/sales/create_order_spec.rb` |
| Modificar | `app/controllers/web/orders_controller.rb` |
| Modificar | `app/views/web/orders/show.html.haml` |

---

## Task 1: Migración — agregar `user_id` a `orders`

**Files:**
- Create: `db/migrate/TIMESTAMP_add_user_to_orders.rb` (generado con rails generate)

- [ ] **Step 1: Generar la migración**

```bash
cd /path/to/app && bundle exec rails generate migration AddUserToOrders user:references
```

Esto genera un archivo en `db/migrate/` con nombre tipo `20260618XXXXXX_add_user_to_orders.rb`.

- [ ] **Step 2: Editar la migración para agregar NOT NULL y on_delete: :restrict**

Abrir el archivo generado y reemplazar su contenido por:

```ruby
class AddUserToOrders < ActiveRecord::Migration[7.2]
  def change
    add_reference :orders, :user, null: false, foreign_key: { on_delete: :restrict }
  end
end
```

- [ ] **Step 3: Correr la migración**

```bash
bundle exec rails db:migrate
```

Salida esperada: `== AddUserToOrders: migrated`

- [ ] **Step 4: Verificar el schema**

```bash
grep -A 2 "user_id" db/schema.rb | grep orders
```

Debe aparecer la columna `t.bigint "user_id", null: false` en la tabla `orders`.

- [ ] **Step 5: Commit**

```bash
git add db/migrate/ db/schema.rb
git commit -m "db: add user_id (NOT NULL, restrict) to orders"
```

---

## Task 2: Modelo `Order` — agregar `belongs_to :user`

**Files:**
- Modify: `app/models/order.rb:1-8`

- [ ] **Step 1: Agregar la asociación**

En `app/models/order.rb`, agregar `belongs_to :user` junto a las otras asociaciones al principio de la clase:

```ruby
class Order < ApplicationRecord
  belongs_to :customer, optional: true
  belongs_to :user
  has_many :order_items, dependent: :destroy
  # ... resto sin cambios
```

- [ ] **Step 2: Verificar que el modelo no requiere validación extra**

La presencia ya está garantizada por `null: false` en la DB y por el servicio. No agregar `validates :user, presence: true` — es redundante.

- [ ] **Step 3: Commit**

```bash
git add app/models/order.rb
git commit -m "feat: Order belongs_to :user"
```

---

## Task 3: Factory de `Order` — agregar asociación `user`

**Files:**
- Modify: `spec/factories/orders.rb`

- [ ] **Step 1: Agregar `association :user` al factory base**

```ruby
FactoryBot.define do
  factory :order do
    association :user
    customer { Customer.mostrador }
    status { "confirmed" }
    order_type { "immediate" }
    total_amount { 100.0 }
    original_total_amount { total_amount }
    channel { nil }
    source { "live" }
    sale_date { Date.current }
    sequence(:paper_number) { |n| format("%04d", n) }

    trait :pending do
      status { "pending" }
    end

    trait :credit_order do
      order_type { "credit" }
      association :customer, factory: [ :customer, :with_credit ]
    end

    trait :cancelled do
      status { "cancelled" }
    end

    trait :on_account do
      order_type { "on_account" }
      status { "pending" }
      contact_name { "Juan Pérez" }
      contact_phone { "11 5555 1234" }
    end

    trait :with_counter_channel do
      channel { "counter" }
    end

    trait :with_whatsapp_channel do
      channel { "whatsapp" }
    end

    trait :with_mercadolibre_channel do
      channel { "mercadolibre" }
    end

    trait :from_paper do
      source { "from_paper" }
      paper_number { "0001" }
      total_amount { 0 }
      sale_date { Date.current }
    end

    trait :live do
      source { "live" }
      sale_date { Date.current }
    end
  end
end
```

- [ ] **Step 2: Correr specs de modelo de Order para asegurar que el factory funciona**

```bash
bundle exec rspec spec/models/order_spec.rb
```

Todos los tests deben pasar (o los que fallaban por otro motivo ya fallaban antes).

- [ ] **Step 3: Commit**

```bash
git add spec/factories/orders.rb
git commit -m "test: add user association to order factory"
```

---

## Task 4: Servicio `Sales::CreateOrder` — agregar parámetro `user:`

**Files:**
- Modify: `app/services/sales/create_order.rb`

- [ ] **Step 1: Escribir el test que falla**

En `spec/services/sales/create_order_spec.rb`, dentro del bloque `RSpec.describe Sales::CreateOrder`, agregar un `let(:user)` al principio del describe principal y un nuevo test que verifique que el user queda asignado a la orden.

Agregar justo debajo de la línea `let!(:stock_location) { create(:stock_location) }`:

```ruby
let(:user) { create(:user) }
```

Y dentro del `context 'with valid immediate order'`, agregar este test nuevo:

```ruby
it 'assigns the user to the order' do
  result = described_class.call(
    customer: customer_without_credit,
    items: [ { product_id: product.id, quantity: 2, unit_price: 100 } ],
    order_type: 'immediate',
    paper_number: '0001',
    user: user
  )

  expect(result.success?).to be true
  expect(result.record.user).to eq(user)
end
```

- [ ] **Step 2: Correr el test nuevo para confirmar que falla**

```bash
bundle exec rspec spec/services/sales/create_order_spec.rb -e "assigns the user"
```

Salida esperada: FAILED — `unknown keyword: user` o similar.

- [ ] **Step 3: Actualizar el servicio**

Reemplazar la firma `self.call` y `initialize` en `app/services/sales/create_order.rb`:

```ruby
def self.call(customer:, items:, order_type:, paper_number:, user:,
              channel: nil, source: "live", sale_date: nil,
              contact_name: nil, contact_phone: nil,
              delivered_product_ids: [])
  new(
    customer: customer,
    items: items,
    order_type: order_type,
    paper_number: paper_number,
    user: user,
    channel: channel,
    source: source,
    sale_date: sale_date,
    contact_name: contact_name,
    contact_phone: contact_phone,
    delivered_product_ids: delivered_product_ids
  ).call
end

def initialize(customer:, items:, order_type:, paper_number:, user:,
               channel: nil, source: "live", sale_date: nil,
               contact_name: nil, contact_phone: nil,
               delivered_product_ids: [])
  @customer              = customer
  @items                 = items.map { |i| i.is_a?(Item) ? i : Item.new(i) }
  @order_type            = order_type
  @paper_number          = paper_number.presence
  @user                  = user
  @channel               = channel
  @source                = source
  @sale_date             = sale_date || Date.current
  @contact_name          = contact_name
  @contact_phone         = contact_phone
  @delivered_product_ids = Array(delivered_product_ids).map(&:to_i)
end
```

Y en el método privado `create_order`, agregar `user: @user` al `Order.create!`:

```ruby
def create_order
  total = calculate_total
  @order = Order.create!(
    customer:              @customer,
    user:                  @user,
    order_type:            @order_type,
    channel:               @channel,
    source:                @source,
    sale_date:             @sale_date,
    paper_number:          @paper_number,
    status:                "pending",
    total_amount:          total,
    original_total_amount: total,
    contact_name:          @contact_name,
    contact_phone:         @contact_phone
  )
end
```

- [ ] **Step 4: Correr el test nuevo para verificar que pasa**

```bash
bundle exec rspec spec/services/sales/create_order_spec.rb -e "assigns the user"
```

Salida esperada: PASSED.

- [ ] **Step 5: Commit del servicio y el test nuevo**

```bash
git add app/services/sales/create_order.rb spec/services/sales/create_order_spec.rb
git commit -m "feat: Sales::CreateOrder accepts and assigns user: param"
```

---

## Task 5: Actualizar todos los calls existentes en `create_order_spec.rb`

**Files:**
- Modify: `spec/services/sales/create_order_spec.rb`

Los tests existentes llaman a `described_class.call(...)` sin `user:` — ahora es un keyword requerido, así que fallarán con `missing keyword: user`.

- [ ] **Step 1: Verificar cuántos calls hay sin `user:`**

```bash
bundle exec rspec spec/services/sales/create_order_spec.rb 2>&1 | grep "missing keyword"
```

- [ ] **Step 2: Agregar `let(:user) { create(:user) }` en los contexts que no lo tienen**

El `let(:user)` ya fue agregado al describe principal en Task 4. Todos los contexts anidados lo heredan automáticamente — no hay que repetirlo.

- [ ] **Step 3: Agregar `user: user` a cada `described_class.call` del spec**

Usar búsqueda y reemplazo en el archivo. Cada bloque de la forma:

```ruby
described_class.call(
  customer: ...,
  items: [...],
  order_type: '...',
  paper_number: '...'
)
```

debe quedar:

```ruby
described_class.call(
  customer: ...,
  items: [...],
  order_type: '...',
  paper_number: '...',
  user: user
)
```

Aplicar a TODOS los `described_class.call` del archivo (aproximadamente 25 ocurrencias). Verificar que ninguno quede sin `user:`.

- [ ] **Step 4: Correr el spec completo para verificar que todos pasan**

```bash
bundle exec rspec spec/services/sales/create_order_spec.rb
```

Salida esperada: todos los tests en verde. Si alguno falla por otra razón, investigar antes de continuar.

- [ ] **Step 5: Commit**

```bash
git add spec/services/sales/create_order_spec.rb
git commit -m "test: pass user: to all Sales::CreateOrder calls in spec"
```

---

## Task 6: Controller — pasar `current_user` al servicio

**Files:**
- Modify: `app/controllers/web/orders_controller.rb:57-68`

- [ ] **Step 1: Agregar `user: current_user` en la llamada al servicio**

En `app/controllers/web/orders_controller.rb`, en el método `create`, agregar el parámetro:

```ruby
def create
  authorize Order, :create?
  result = Sales::CreateOrder.call(
    customer: find_or_create_customer,
    items: parse_items,
    order_type: params.dig(:order, :order_type) || "immediate",
    channel: params.dig(:order, :channel),
    source: params[:source] || "live",
    sale_date: params[:sale_date],
    paper_number: params[:paper_number],
    contact_name: params[:contact_name],
    contact_phone: params[:contact_phone],
    delivered_product_ids: Array(params[:delivered_product_ids]),
    user: current_user
  )

  if result.success?
    redirect_to web_order_path(result.record),
                notice: "Nota #{result.record.paper_number} creada — pendiente de cobro"
  else
    flash.now[:alert] = result.errors.join(", ")
    @order = Order.new
    render :new, status: :unprocessable_entity
  end
end
```

- [ ] **Step 2: Correr el spec de requests de orders**

```bash
bundle exec rspec spec/requests/web/orders_spec.rb
```

Salida esperada: todos los tests en verde. Si algún test de request falla por falta de `user:`, revisar si construyen `Order` directamente o usan la factory — la factory ya tiene `association :user` desde Task 3.

- [ ] **Step 3: Commit**

```bash
git add app/controllers/web/orders_controller.rb
git commit -m "feat: pass current_user to Sales::CreateOrder in OrdersController"
```

---

## Task 7: Vista — reemplazar "Sistema" por el nombre del usuario

**Files:**
- Modify: `app/views/web/orders/show.html.haml:115-117`

La vista ya tiene el bloque "Registrado por" en la línea ~115 con el texto hardcodeado "Sistema":

```haml
.flex.flex-col
  %label.text-xs.font-medium.text-gray-500.uppercase.tracking-wider.mb-1 Registrado por
  %span.text-sm.text-gray-700 Sistema
```

- [ ] **Step 1: Reemplazar el texto hardcodeado por el nombre del usuario**

Cambiar esas tres líneas por:

```haml
.flex.flex-col
  %label.text-xs.font-medium.text-gray-500.uppercase.tracking-wider.mb-1 Registrado por
  %span.text-sm.text-gray-700= @order.user.name
```

- [ ] **Step 2: Correr el suite completo para detectar regresiones**

```bash
bundle exec rspec
```

Salida esperada: todos los tests en verde.

- [ ] **Step 3: Commit final**

```bash
git add app/views/web/orders/show.html.haml
git commit -m "feat: show vendedor name in order detail view"
```

---

## Verificación final

- [ ] Correr el suite completo una vez más limpio:

```bash
bundle exec rspec
```

- [ ] Confirmar que `orders.user_id` es `NOT NULL` en el schema:

```bash
grep "user_id" db/schema.rb
```

Debe aparecer `t.bigint "user_id", null: false` en la tabla `orders`.
