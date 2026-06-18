# Design: Registrar usuario vendedor en órdenes

**Fecha:** 2026-06-18
**Feature:** Feat — Order#user (vendedor que creó la venta)

---

## Contexto

Las órdenes (`Order`) no registran quién realizó la venta. Se necesita asociar cada venta al usuario (`User`) que la creó, usando `current_user` en los flujos web.

Precedente en el proyecto: `sales_ledger_entries` ya usa `seller_user_id` como FK a `users`.

---

## Decisiones de diseño

- **Columna:** `user_id` (convención Rails estándar). Se descartó `created_by_user_id` por YAGNI — hoy solo existe un rol relevante por orden.
- **Nullable:** NO — `NOT NULL` en DB. No hay datos de producción existentes, así que no es necesario tolerar nulos.
- **On delete:** `restrict` — no se puede borrar un usuario que tenga ventas asociadas.
- **Punto de asignación:** el servicio `Sales::CreateOrder`, no el controller directamente (thin controller).

---

## Cambios por capa

### 1. Migración

```ruby
add_reference :orders, :user, null: false, foreign_key: { on_delete: :restrict }
```

Agrega `user_id bigint NOT NULL` con FK a `users`.

### 2. Modelo `Order`

```ruby
belongs_to :user
```

Sin validación de presencia explícita — garantizada por `NOT NULL` en DB y por el servicio.

### 3. Servicio `Sales::CreateOrder`

Agrega `user:` como parámetro obligatorio (sin default):

```ruby
def self.call(customer:, items:, order_type:, paper_number:, user:, ...)
```

Lo pasa a `Order.create!`:

```ruby
@order = Order.create!(..., user: @user)
```

### 4. Controller `Web::OrdersController#create`

```ruby
result = Sales::CreateOrder.call(
  ...,
  user: current_user
)
```

Un solo parámetro extra. Sin lógica adicional.

### 5. Vista `web/orders/show.html.haml`

Agrega fila "Vendedor" con `order.user.name` en la tabla de detalles de la orden.

---

## Specs afectados

- Specs existentes de `Sales::CreateOrder` necesitan recibir `user:` válido — ajuste mínimo en factories/llamadas.
- No se requieren specs nuevos para el controller (el cambio es trivial). Se puede agregar un assertion en el spec del servicio que verifique que `result.record.user` == el user pasado.

---

## Fuera de alcance

- Mostrar el vendedor en el índice de órdenes.
- Filtrar/buscar órdenes por vendedor.
- Registrar el usuario en otros flujos (cancelación, cobro).
