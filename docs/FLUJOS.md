# FLUJOS.md

---

## Flujos de negocio – Sistema de ventas e inventario de repuestos (V1)

### 0. Supuestos generales

* Un solo local físico de venta de repuestos.
* Se vende en **pesos argentinos (ARS)**.
* La mayoría de las compras de mercadería se hacen en **USD**, tomando un tipo de cambio manual.
* No se maneja número de chasis / VIN en V1.
* Hay dos tipos de “cliente”:

  * **Cliente Mostrador** (genérico, para consumidores finales).
  * **Clientes con cuenta corriente** (talleres, mecánicos, tiendas, empresas).
* No se modela contabilidad completa ni gastos generales en el sistema (eso va por fuera).
* El costo de courier / flete **no se incluye** en el costo del producto en V1.

---

## 1. Venta de mostrador contado (cliente genérico)

Flujo típico cuando viene alguien “suelo” a comprar al local.

1. El vendedor (Alfredo u otro) determina el repuesto correcto usando su experiencia o sistemas externos.

   * El sistema **no** participa en la parte de chasis / compatibilidad.
2. En el sistema:

   * Se crea una **nueva venta**.
   * Cliente = `Cliente Mostrador` (cliente genérico).
   * Tipo de venta = `contado`.
   * Canal (opcional): `mostrador`, `whatsapp`, `mercado_libre_manual`, etc.
   * Se agregan los ítems:

     * producto,
     * cantidad,
     * precio unitario en ARS (normalmente tomado del precio del producto).
3. El sistema:

   * Valida que haya **stock suficiente** para cada producto.
   * Calcula el **total** de la venta.
4. Al **confirmar** la venta:

   * Se crea el registro de venta.
   * Se generan **movimientos de stock negativos** por cada ítem.
   * No se crea ningún registro de `Payment` (se asume cobro inmediato).
5. Si se cometió un error (producto equivocado, cantidad, etc.):

   * Se **anula** la venta:

     * estado de la venta pasa a `anulada`,
     * se generan movimientos de stock inversos (el stock vuelve).
   * Se crea una **nueva venta** con los datos correctos.

> En resumen: venta de contado = no genera saldo, no usa el modelo de pagos.

---

## 2. Venta a cliente con cuenta corriente (taller / mecánico / tienda)

Flujo cuando se vende a crédito a un cliente que tiene cuenta corriente.

1. El cliente ya existe registrado como:

   * taller, mecánico, empresa, u otra tienda,
   * con flag de que maneja **cuenta corriente**.
2. El cliente encarga repuestos (en persona, por teléfono, WhatsApp, etc.).
3. En el sistema:

   * Se crea una **nueva venta**.
   * Cliente = cliente real (taller/mecánico/tienda).
   * Tipo de venta = `cuenta_corriente`.
   * Canal: `mostrador`, `whatsapp`, etc.
   * Se agregan ítems con producto, cantidad, precio unitario.
4. El sistema:

   * Valida stock disponible.
   * Calcula el total.
5. Al **confirmar**:

   * Se crea la venta.
   * Se generan movimientos de stock negativos.
   * La venta entra en el cálculo de **saldo del cliente**.

Cálculo de saldo del cliente:

```text
saldo = SUM(ventas_a_credito_no_anuladas.total) - SUM(pagos.amount)
```

6. Si la venta fue mal cargada (precio, cantidad, producto):

   * Se **anula** la venta original.
   * Se crean movimientos de stock inversos que devuelven el stock.
   * Se registra una nueva venta con los datos correctos.

> Importante: los pagos no se ligan a una venta específica, sino al cliente en general.
> Al anular una venta, el saldo se recalcula automáticamente con la fórmula global.

---

## 3. Registro de pago de cuenta corriente

Flujo cuando un cliente de cuenta corriente viene a pagar algo de su deuda.

1. Un taller / mecánico / tienda decide pagar un monto (total o parcial) de su cuenta corriente.

2. En el sistema:

   * Se va a la sección de **Cobranzas / Pagos**.
   * Se elige el cliente correspondiente.
   * Se registra un **nuevo pago** con:

     * monto en ARS,
     * método de pago (efectivo, transferencia, etc.),
     * fecha,
     * notas (opcional: referencia de transferencia, comentario, etc.).

3. El sistema:

   * Crea un registro `Payment` asociado al cliente.
   * Recalcula el saldo del cliente con la fórmula:

     ```text
     saldo = SUM(ventas_a_credito_no_anuladas.total) - SUM(payments.amount)
     ```

4. No se hace “matching” del pago contra una venta específica en V1:

   * es un modelo global de saldo (estado de cuenta).

5. Si el pago se cargó mal:

   * En V1 se asume que se puede:

     * borrar el pago (si fue un error total),
     * o ingresar un segundo pago negativo / ajuste (esto se podría modelar luego si hace falta).

---

## 4. Compra de mercadería (reposición de stock)

Flujo cuando llega mercadería importada (por ejemplo desde USA, China, Taiwán, Japón).

1. Llega un lote de mercadería al depósito.
2. En el sistema:

   * Se crea una **nueva compra**.
   * Se registra:

     * proveedor (texto libre o listado),
     * fecha de la compra,
     * moneda = `USD`,
     * tipo de cambio usado para esta compra (ej: 1 USD = 1200 ARS).
   * Se agregan ítems:

     * producto,
     * cantidad,
     * costo unitario en USD.
3. El sistema:

   * Calcula para cada ítem:

     * `costo_unitario_ars = costo_unitario_usd * tipo_cambio`.
   * Puede actualizar el costo promedio en ARS del producto (dependiendo de cómo se implemente la lógica de costos).
4. Al **confirmar** la compra:

   * Se crean **movimientos de stock positivos** para cada producto (entra stock).
5. El costo de courier, impuestos, flete y otros gastos logísticos:

   * **no se incluye** en el costo del producto dentro del sistema en V1.
   * Se asume que esos costos se manejan por fuera (Excel, contabilidad externa, etc.).

---

## 5. Ajuste de stock (reconteo físico)

Flujo para corregir diferencias entre el stock del sistema y el stock real en el depósito.

1. Se realiza un reconteo físico de ciertos productos (o de todo el depósito).
2. Para cada producto con diferencia:

   * Se compara el stock “esperado” (según el sistema) con el stock real contado.
3. En el sistema:

   * Se crea un **ajuste de stock**:

     * producto,
     * cantidad real,
     * motivo del ajuste (pérdida, error de carga, robo, rotura, etc.).
4. El sistema:

   * Calcula la diferencia = `cantidad_real - cantidad_en_sistema`.
   * Crea un `StockMovement` de tipo `adjustment`:

     * cantidad positiva (si faltaba stock en sistema),
     * o negativa (si había de más).
5. Después del ajuste:

   * el stock del producto vuelve a reflejar la realidad física.

> Los ajustes de stock son explícitos, no se modifican números “a mano” en el producto.
> Siempre se ve el historial de por qué el stock cambió.

---

## 6. Anulación de venta (contado o cuenta corriente)

Flujo para deshacer una venta completa por error o devolución total.

1. Se identifica una venta que necesita ser revertida:

   * por error al cargar productos/cantidades,
   * porque el cliente devolvió todo.

2. En el sistema:

   * Se abre la venta.
   * Se usa la acción **“Anular venta”** (o equivalente).

3. El sistema:

   * Cambia el estado de la venta a `anulada`.
   * Genera movimientos de stock inversos a los originales:

     * por cada ítem vendido, se crea un movimiento con la cantidad opuesta (vuelve al stock).

4. Impacto en saldo:

   * Si es venta de **contado**:

     * no afecta saldo porque esa venta nunca entró al saldo.
     * el efecto es solo en stock e historial.
   * Si es venta de **cuenta_corriente**:

     * la venta deja de contarse en la suma de ventas a crédito.
     * el saldo del cliente se recalcula automáticamente:

       ```text
       saldo = SUM(ventas_a_credito_no_anuladas.total) - SUM(payments.amount)
       ```

5. Correcciones parciales:

   * En V1, en vez de manejar devoluciones parciales complejas, se recomienda:

     * anular la venta original,
     * crear una nueva venta con la cantidad correcta de productos.

---

## 7. Actualización de precios de productos

Flujo para subir precios cuando sube el dólar o cambian los costos.

1. El negocio decide ajustar precios (por ejemplo subir todos un X%).
2. En el sistema:

   * Se va a una pantalla de **Ajuste masivo de precios** (cuando exista).
   * Se pueden definir reglas:

     * subir todos los productos un X%,
     * o por categoría (frenos, motor, etc.).
3. El sistema:

   * Calcula los nuevos precios sugeridos.
   * Muestra un resumen antes de aplicar.
4. Al confirmar:

   * Actualiza los precios de venta de los productos.
5. El costo histórico no se modifica; solo el **precio de venta**.

> Este flujo puede ser simple en V1 (por ejemplo, un campo “nuevo multiplicador” + botón “aplicar”),
> y evolucionar a algo más detallado más adelante.

---

Si quieres, el siguiente paso puede ser:

* tomar este documento y yo te lo convierto en un esqueleto más tipo `DOMAIN_SPEC.md` completo (agregando una pequeña sección de entidades arriba),
  o lo dejamos así tal cual como “Flujos V1” y le sumamos solo una mini intro para Claude tipo: “Este documento describe cómo debe comportarse el sistema a nivel negocio. No hables de Rails, solo respeta estos flujos”.
