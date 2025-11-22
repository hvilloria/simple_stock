# FLUJOS.md

---

## Flujos de negocio – Sistema de ventas e inventario de repuestos (V1)

### 0. Supuestos generales

* Un solo local físico de venta de repuestos.
* Se vende en **pesos argentinos (ARS)**.
* La mayoría de las compras de mercadería se hacen en **USD**, tomando un tipo de cambio manual.
* No se maneja número de chasis / VIN en V1.
* Hay dos tipos de "cliente":

  * **Cliente Mostrador** (genérico, para consumidores finales).
  * **Clientes con cuenta corriente** (talleres, mecánicos, tiendas, empresas).
* No se modela contabilidad completa ni gastos generales en el sistema (eso va por fuera).
* El costo de courier / flete **no se incluye** en el costo del producto en V1.

### 0.1. Tipos de productos

El negocio maneja dos tipos de productos:

* **Productos OEM (Original Equipment Manufacturer)**:
  * Repuestos de la marca original del vehículo (ej: Honda, Toyota, etc.)
  * Son los productos "originales" o de fábrica
  * Generalmente más caros pero con garantía de calidad original

* **Productos Aftermarket (Alternativos)**:
  * Repuestos compatibles fabricados por otras marcas (ej: TRW, Bosch, etc.)
  * Son alternativas más económicas o de diferentes calidades
  * Los clientes suelen preguntar por el **origen/país de fabricación**:
    * Japón (premium, mayor calidad)
    * Taiwan (calidad intermedia)
    * China (económico)
    * USA, Alemania, Corea, Brasil, etc.

**Ejemplo de venta típica:**
1. Cliente pregunta por pastillas de freno para Honda Fit 2015
2. Alfredo ofrece:
   - Opción 1: Pastillas Honda originales (OEM) - $15,000
   - Opción 2: Pastillas TRW fabricadas en Japón - $12,000
   - Opción 3: Pastillas TRW fabricadas en China - $8,000
3. Cliente decide según su presupuesto y preferencia de calidad

**Almacenamiento en el sistema:**
- Cada variante es un producto distinto con su propio SKU
- El sistema debe permitir identificar si es OEM o aftermarket
- Para aftermarket, debe registrarse el país de origen
- Un mismo código de producto puede tener múltiples versiones según origen

---

## 1. Venta de mostrador contado (cliente genérico)

Flujo típico cuando viene alguien "suelo" a comprar al local.

1. El vendedor (Alfredo u otro) determina el repuesto correcto usando su experiencia o sistemas externos.

   * El sistema **no** participa en la parte de chasis / compatibilidad.
2. En el sistema:

   * Se crea una **nueva venta**.
   * Cliente = `Cliente Mostrador` (cliente genérico).
   * Tipo de venta = `cash` (contado).
   * Canal (opcional): `counter`, `whatsapp`, `mercadolibre`, etc.
   * Se agregan los ítems:

     * producto (puede ser OEM o aftermarket),
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

     * estado de la venta pasa a `cancelled`,
     * se generan movimientos de stock inversos (el stock vuelve).
   * Se crea una **nueva venta** con los datos correctos.

> En resumen: venta de contado = no genera saldo, no usa el modelo de pagos.

---

## 2. Venta a cliente con cuenta corriente (taller / mecánico / tienda)

Flujo cuando se vende a crédito a un cliente que tiene cuenta corriente.

1. El cliente ya existe registrado como:

   * taller, mecánico, empresa, u otra tienda,
   * con flag de que maneja **cuenta corriente** (`has_credit_account = true`).
2. El cliente encarga repuestos (en persona, por teléfono, WhatsApp, etc.).
3. En el sistema:

   * Se crea una **nueva venta**.
   * Cliente = cliente real (taller/mecánico/tienda).
   * Tipo de venta = `credit` (cuenta corriente).
   * Canal: `counter`, `whatsapp`, etc.
   * Se agregan ítems con producto, cantidad, precio unitario.
4. El sistema:

   * Valida stock disponible.
   * Valida que el customer tenga `has_credit_account = true`.
   * Calcula el total.
5. Al **confirmar**:

   * Se crea la venta.
   * Se generan movimientos de stock negativos.
   * La venta entra en el cálculo de **saldo del cliente**.

Cálculo de saldo del cliente:

```text
saldo = SUM(ventas_a_credito_no_canceladas.total) - SUM(pagos.amount)
```

6. Si la venta fue mal cargada (precio, cantidad, producto):

   * Se **anula** la venta original (status = `cancelled`).
   * Se crean movimientos de stock inversos que devuelven el stock.
   * Se registra una nueva venta con los datos correctos.

> **Importante:** 
> - Un mismo cliente puede tener ventas `cash` (contado) Y ventas `credit` (a crédito)
> - Solo las ventas tipo `credit` entran en el cálculo de saldo
> - Los pagos no se ligan a una venta específica, sino al cliente en general
> - Al anular una venta, el saldo se recalcula automáticamente con la fórmula global

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
     saldo = SUM(ventas_credit_no_canceladas.total) - SUM(payments.amount)
     ```

4. No se hace "matching" del pago contra una venta específica en V1:

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
     * moneda = `USD` o `ARS`,
     * tipo de cambio usado para esta compra si es USD (ej: 1 USD = 1200 ARS).
   * Se agregan ítems:

     * producto (debe existir previamente con su SKU, origin, product_type),
     * cantidad,
     * costo unitario en la moneda especificada (USD o ARS).
3. El sistema:

   * Si la compra es en USD:
     * Calcula para cada ítem: `costo_unitario_ars = costo_unitario_usd * tipo_cambio`.
     * Guarda en el producto: `cost_unit` en la moneda original y `cost_currency` ('USD' o 'ARS').
   * Si la compra es en ARS:
     * Guarda directamente `cost_unit` en ARS y `cost_currency = 'ARS'`.
   * Puede actualizar el costo promedio del producto (dependiendo de cómo se implemente la lógica de costos).
4. Al **confirmar** la compra:

   * Se crean **movimientos de stock positivos** para cada producto (entra stock).
   * Se actualiza el `cost_unit` y `cost_currency` del producto con el último costo de compra.
5. El costo de courier, impuestos, flete y otros gastos logísticos:

   * **no se incluye** en el costo del producto dentro del sistema en V1.
   * Se asume que esos costos se manejan por fuera (Excel, contabilidad externa, etc.).

**Nota sobre productos OEM vs Aftermarket:**
- Los productos OEM y aftermarket con diferentes orígenes tienen SKUs distintos
- Al hacer una compra, se selecciona el producto específico (ej: "Pastillas TRW - Japón" vs "Pastillas TRW - China")
- El sistema no convierte automáticamente entre variantes; cada una es independiente

---

## 5. Ajuste de stock (reconteo físico)

Flujo para corregir diferencias entre el stock del sistema y el stock real en el depósito.

1. Se realiza un reconteo físico de ciertos productos (o de todo el depósito).
2. Para cada producto con diferencia:

   * Se compara el stock "esperado" (según el sistema) con el stock real contado.
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

> Los ajustes de stock son explícitos, no se modifican números "a mano" en el producto.
> Siempre se ve el historial de por qué el stock cambió.

---

## 6. Anulación de venta (contado o cuenta corriente)

Flujo para deshacer una venta completa por error o devolución total.

1. Se identifica una venta que necesita ser revertida:

   * por error al cargar productos/cantidades,
   * porque el cliente devolvió todo.

2. En el sistema:

   * Se abre la venta.
   * Se usa la acción **"Anular venta"** (o equivalente).

3. El sistema:

   * Cambia el estado de la venta a `cancelled`.
   * Genera movimientos de stock inversos a los originales:

     * por cada ítem vendido, se crea un movimiento con la cantidad opuesta (vuelve al stock).

4. Impacto en saldo:

   * Si es venta de **cash** (contado):

     * no afecta saldo porque esa venta nunca entró al saldo.
     * el efecto es solo en stock e historial.
   * Si es venta de **credit** (cuenta corriente):

     * la venta deja de contarse en la suma de ventas a crédito.
     * el saldo del cliente se recalcula automáticamente:

       ```text
       saldo = SUM(ventas_credit_no_canceladas.total) - SUM(payments.amount)
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

   * Actualiza los `price_unit` de los productos seleccionados.
5. El costo histórico (`cost_unit`) no se modifica; solo el **precio de venta** (`price_unit`).

> Este flujo puede ser simple en V1 (por ejemplo, un campo "nuevo multiplicador" + botón "aplicar"),
> y evolucionar a algo más detallado más adelante.

---

## 8. Gestión de productos OEM vs Aftermarket

### 8.1. Creación de productos

Al crear un nuevo producto en el sistema:

1. Se debe especificar:
   * SKU único
   * Nombre descriptivo
   * Marca (ej: Honda, TRW, Bosch)
   * Categoría (frenos, motor, suspensión, etc.)
   * Precio de venta (`price_unit`)
   * Costo (`cost_unit` y `cost_currency`: USD o ARS)
   * **Tipo de producto**: OEM o aftermarket
   * **Origen** (opcional para OEM, importante para aftermarket): japan, china, taiwan, usa, germany, korea, brazil

2. Ejemplos de productos:

   **Producto OEM:**
   ```
   SKU: HDC001-OEM
   Nombre: Disco de Freno Delantero Honda Fit 2015-2020
   Marca: Honda
   Tipo: OEM
   Origen: japan
   Precio: $15,000
   Costo: $80 USD
   ```

   **Productos Aftermarket (diferentes orígenes):**
   ```
   SKU: TRW-DF-FIT-JP
   Nombre: Disco de Freno Delantero Fit (TRW - Japón)
   Marca: TRW
   Tipo: aftermarket
   Origen: japan
   Precio: $12,000
   Costo: $60 USD
   
   SKU: TRW-DF-FIT-CN
   Nombre: Disco de Freno Delantero Fit (TRW - China)
   Marca: TRW
   Tipo: aftermarket
   Origen: china
   Precio: $8,000
   Costo: $35 USD
   ```

### 8.2. Búsqueda y selección durante la venta

1. Alfredo busca el producto por nombre, código o compatibilidad
2. El sistema muestra todas las variantes disponibles:
   - Original (OEM) si existe
   - Alternativos con sus respectivos orígenes
3. Se muestra claramente el origen en la lista de resultados
4. Alfredo selecciona el producto específico que el cliente eligió
5. La venta registra exactamente qué variante se vendió

---

## Apéndice: Campos del modelo Product

Para referencia técnica, los productos tienen los siguientes campos clave:

* `sku` - Código único del producto (string, unique)
* `name` - Nombre descriptivo (string)
* `category` - Categoría (string): frenos, motor, suspension, transmision, electrico, carroceria, filtros, lubricantes
* `cost_unit` - Costo promedio ponderado de todas las compras confirmadas (decimal)
  * Se recalcula automáticamente al confirmar/anular compras
  * Usado para calcular márgenes y rentabilidad
  * NO es el "último costo" sino el promedio ponderado histórico
* `cost_currency` - Moneda del costo promedio (string): 'USD' o 'ARS' (típicamente 'USD')
* `price_unit` - Precio de venta en ARS (decimal)
* `current_stock` - Stock actual (integer, campo cacheado)
* `active` - Producto activo (boolean)
* `origin` - País de origen (string): japan, china, taiwan, usa, germany, korea, brazil, etc.
* `product_type` - Tipo de producto (string): 'oem' o 'aftermarket'
* `brand` - Marca del producto (string)

**Notas importantes:**
- `current_stock` es un campo cacheado que se actualiza automáticamente via callbacks de StockMovement
- `cost_unit` es el costo promedio ponderado de todas las compras confirmadas
  * Ejemplo: Compra 1 (5 unidades @ $10 USD) + Compra 2 (5 unidades @ $20 USD) = Costo promedio $15 USD
  * Se recalcula automáticamente cuando se confirma o anula una compra
  * Para calcular el promedio, todas las compras se convierten a USD para uniformidad
- Para calcular margen, si el costo es en USD, debe convertirse a ARS usando el tipo de cambio actual
- `origin` y `product_type` son opcionales pero recomendados para mejor gestión del inventario