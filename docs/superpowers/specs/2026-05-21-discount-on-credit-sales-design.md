# feat_09 — Descuento por producto en ventas a crédito

## Objetivo

Permitir que el operador aplique descuentos **por producto** (hasta 20%) en
órdenes a crédito **al momento del cobro**. El descuento queda congelado en
el primer cobro de la orden y reduce permanentemente su `total_amount`.

Inmediatas (feat_08) no se tocan funcionalmente: siguen con descuento global
hasta 10% aplicado al crear la orden.

## Reglas del negocio

1. **Granularidad:** descuento por `order_item`, no global.
2. **Cap:** `0 ≤ discount_percent ≤ 20` por ítem.
3. **Lifecycle:** en el momento del primer cobro de la orden el operador
   puede setear `discount_percent` en cada ítem. Apenas existe un
   `PaymentAllocation` para esa orden, los descuentos quedan congelados —
   cobros posteriores no pueden modificarlos.
4. **Total efectivo:** `order.total_amount` pasa a representar el total
   post-descuento. `order.original_total_amount` (introducido en feat_08)
   conserva el snapshot pre-descuento. `outstanding_balance` y
   `customer.current_balance` heredan el nuevo `total_amount` sin cambios.
5. **Monto a cobrar:** el campo "Cobrar" arranca con el nuevo total y es
   editable hacia abajo para cobros parciales.

## Modelo de datos

Sin migraciones nuevas. Se reutilizan las columnas creadas en feat_08:

- `order_items.discount_percent` — `decimal(5,2)`, default `0`, ya validada
  `0..20`.
- `orders.original_total_amount` — `decimal(10,2)`, ya seteada en creación.

### Validaciones

`OrderItem`:

- La validación numérica `0..20` se mantiene.
- Se elimina la rama de `discount_within_order_type_cap` que hoy bloquea
  `discount_percent > 0` para `credit_order_type?`. El cap único pasa a ser
  20% sin importar el tipo de orden.
- La rama que limita inmediatas a 10% se conserva.

## Capa de servicio

Se extiende `Payments::AllocatePayment` (única vía de cobro) para aceptar
descuentos opcionales por ítem dentro de cada allocation:

```ruby
Payments::AllocatePayment.call(
  customer: customer,
  payment_date: Date.today,
  notes: "Pago parcial",
  allocations: [
    {
      order_id: 312,
      amount: 16_600,
      payment_method: "cash",
      item_discounts: { 998 => 10, 999 => 20, 1000 => 0 }  # order_item_id => percent
    }
  ]
)
```

### Flujo dentro de la transacción

Para cada `allocation`:

1. Si `item_discounts` está presente:
   - Si `order.payment_allocations.exists?` → ignorar `item_discounts`
     (orden ya bloqueada).
   - Si no:
     - Validar `0 ≤ percent ≤ 20` para cada valor recibido.
     - Validar que cada `order_item_id` pertenezca a `order` (param hardening).
     - Asignar `discount_percent` en los `order_items` correspondientes.
     - Recalcular `order.total_amount`:
       ```ruby
       order.total_amount = order.order_items.sum do |oi|
         oi.quantity * oi.unit_price * (1 - oi.discount_percent / 100.0)
       end
       order.save!
       ```
2. Crear `Payment` + `PaymentAllocation` con la lógica actual, contra el
   `total_amount` ya recalculado.
3. La regla existente `amount ≤ order.outstanding_balance` se aplica al
   nuevo total automáticamente.

### Errores

- `percent` fuera de `0..20` → `Result.failure?` con
  `errors: ["Descuento fuera de rango (0-20%)"]`.
- `order_item_id` que no pertenece a la orden → ignorado silenciosamente
  (no es input legítimo).
- `item_discounts` enviado a orden ya con allocations → ignorado
  silenciosamente (la UI no lo permite; defensa en backend).

## Capa de controlador

`Web::Customers::PaymentsController#parsed_allocations` extrae el nuevo
campo cuando viene:

```ruby
{
  order_id: row[:order_id],
  amount: row[:amount].to_f,
  payment_method: row[:payment_method],
  item_discounts: row[:discounts]&.to_unsafe_h&.transform_values(&:to_i)
}
```

## UI

Sustituye la tabla actual en `app/views/web/customers/payments/new.html.haml`
por una grilla de cards (una por orden pendiente).

### Header de la card (siempre visible)

- Checkbox de inclusión.
- Título: `Orden #<id>/<paper_number>` cuando hay `paper_number`; solo
  `Orden #<id>` si no.
- Fecha de venta.
- Total original y pendiente.
- Badge `descuentos congelados` cuando `order.payment_allocations.exists?`.
- Toggle `N productos ▸/▾`.

### Cuerpo (productos)

Tabla `| producto | cant | % desc | subtotal |`:

- Colapsado por default.
- Se abre automáticamente al tildar el checkbox de la orden.
- Se puede abrir/cerrar manualmente con el toggle aunque la orden no esté
  tildada.
- `% desc` es un `select` con presets `0 / 5 / 10 / 15 / 20`, default `0`.
- En órdenes bloqueadas, el `select` renderiza deshabilitado mostrando el
  porcentaje ya fijado.

### Footer de la card

- "Total con descuento: `<s>$original</s> → $nuevo`" — solo se muestra
  cuando hay al menos un % > 0.
- Input `Cobrar` con default = nuevo total, `min=0`, `max=<nuevo_total>`.

### Resumen superior

La card de resumen existente ("Deuda total / Cobrando ahora / Saldo
restante / Órdenes incluidas") queda sin cambios estructurales; sus
números los recalcula el Stimulus contra los totales post-descuento.

### Stimulus

Se extiende `payment_allocation_controller.js` (sin controller nuevo) con:

- `discountChanged(event)` — recalcula subtotal de fila, total de card y
  resumen global.
- `toggleRow(event)` — ya expande/colapsa al tildar; ahora también pinta
  inputs según el estado locked.
- Target nuevos: `discountSelect`, `productRow`, `cardSubtotal`,
  `cardOriginal`.

## Testing

`spec/models/order_item_spec.rb`:

- Item en orden `credit` con `discount_percent: 20` es válido.
- Item en orden `credit` con `discount_percent: 21` es inválido.

`spec/services/payments/allocate_payment_spec.rb`:

- Primer cobro con `item_discounts` válidos: `order_items.discount_percent`
  actualizados, `order.total_amount` recalculado, `original_total_amount`
  intacto, `PaymentAllocation` creado.
- Segundo cobro a la misma orden con `item_discounts`: descuentos
  ignorados, allocation aplicada normalmente, totales sin tocar.
- `percent` fuera de `0..20` → `Result.failure?`.
- `order_item_id` ajeno a la orden → ignorado, resto del cobro procede.

`spec/requests/web/customers/payments_spec.rb`:

- POST con `discounts[order_item_id]` rellena descuentos, persiste el
  cobro, y `customer.current_balance` refleja el total post-descuento.

## Scope explícitamente fuera

- Exportar resumen del cobro a PDF/whatsapp (queda para feat_10).
- Editar descuentos después del primer cobro.
- Descuentos por línea en ventas inmediatas (siguen siendo globales).
