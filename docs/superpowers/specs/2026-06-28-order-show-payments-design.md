# Resumen de pagos en el show de la venta — Diseño

**Fecha:** 2026-06-28
**Pendientes que cierra:** #2 ("mostrar los pagos relacionados a las órdenes en el show") y #7 ("en la vista de una venta hecha mostrar cuánto se pagó y cómo se pagó").

## Problema

El show de una orden (`app/views/web/orders/show.html.haml`) hoy solo muestra los pagos
para ventas a **crédito** (bloque "Pagos de esta Venta" en la columna derecha), y ese
bloque **no muestra el método de pago** — solo fecha y monto. Las ventas de contado
(`immediate`) y a cuenta (`on_account`) no muestran ningún detalle de cobro.

## Solución

Una card **"Resumen de pagos"** en la **columna principal** del show (`lg:col-span-2`),
ubicada **debajo de la card "Productos Vendidos"**, visible para **todas las ventas no
canceladas** (immediate, credit, on_account).

### Contenido de la card

- **Tabla**, una fila por `PaymentAllocation` de la orden:
  - **Fecha** → `payment.payment_date` (formato de fecha existente, ej. `:friendly` / `:default` ya usado en el show).
  - **Método** → `Payment.method_label(payment.payment_method)`, mostrado como badge de color (Efectivo = emerald, bancarios/MP = blue, siguiendo el estilo de tags del show).
  - **Monto** → `allocation.amount` con `currency_ar`.
  - Orden: por `payment.payment_date` ascendente (historial cronológico), igual que el bloque de crédito actual.
- **Pie de tabla:**
  - **Total cobrado** = suma de `allocation.amount`.
  - **Pendiente** = `order.outstanding_balance`, resaltado (ámbar si > 0, emerald si 0).

### Estado vacío

Cuando la orden no tiene allocations (ej. nota de contado pendiente que caja aún no
cobró): texto *"Sin cobros registrados todavía"* + el **Pendiente** con el total a cobrar
resaltado. (Las ventas canceladas también caen acá porque al cancelar se destruyen las
allocations — ver abajo.)

### Canceladas

`Sales::CancelOrder` destruye las `payment_allocations` de la orden, así que una venta
cancelada muestra el **estado vacío**. En canceladas **se omite la línea "Pendiente"**
(ya existe el banner de "Venta Cancelada"). La card respeta el `opacity-75` que el show
aplica al resto de las cards cuando la orden está cancelada.

### Limpieza

Se **elimina** el bloque viejo "Pagos de esta Venta" de la columna derecha (hoy condicionado
a `@order.credit_order_type?`, aprox. líneas 304-328). La card nueva lo reemplaza para todos
los tipos de venta, evitando duplicar la info en ventas a crédito.

## Alcance técnico

- **Único archivo a tocar:** `app/views/web/orders/show.html.haml`.
- **Sin migraciones. Sin cambios en controller, servicios ni modelos.**
- Los datos ya están cargados: `Web::OrdersController#load_order` hace
  `includes(... payment_allocations: :payment)`.
- Helpers ya disponibles: `currency_ar`, `Payment.method_label`, `l(...)` para fechas.

## Fuera de alcance

- **"Quién cobró / vendedor"**: el modelo `Payment` no guarda el usuario/cajero que registró
  el cobro; mostrarlo requeriría una migración. Se relaciona con los pendientes #8 y #9 y se
  trata por separado.
- **Sección global "Pagos" en el sidebar**: feature aparte, se diseña después.

## Verificación

- Render correcto del show para: contado pendiente (estado vacío), contado cobrado
  (1+ métodos), crédito con cobros parciales, a cuenta con cobros parciales, y cancelada
  (estado vacío sin "Pendiente").
- El bloque viejo de crédito ya no aparece.
- No quedan referencias rotas al bloque eliminado.
