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

### 4.1. Compra de mercadería - Interfaz Web (Nueva Compra)

Flujo detallado de uso de la interfaz web para registrar una compra de mercadería.

**Acceso:**
* Navegación: `Facturas → Nueva Factura`
* URL: `/web/invoices/new`

**Paso 1: Información de la compra**

1. **Seleccionar proveedor:**
   * Lista desplegable con todos los proveedores activos
   * Campo requerido
   * Ejemplo: "Toyota Japan Co", "USA Auto Parts Inc", etc.

2. **Seleccionar moneda:**
   * Radio buttons visuales: USD o ARS
   * Por defecto: USD (mayoría de compras son en dólares)
   * USD: compras de importación (China, USA, Japón, etc.)
   * ARS: compras locales (excepcionales)

3. **Tipo de cambio (solo si USD):**
   * Campo numérico que aparece solo al seleccionar USD
   * Campo requerido para compras en USD
   * Ejemplo: 1200.00 (representa 1 USD = 1200 ARS)
   * Este TC se guarda con la compra y se usa para calcular el costo en ARS

4. **Fecha de compra:**
   * Campo de fecha
   * Por defecto: fecha actual
   * Permite registrar compras pasadas si es necesario

5. **Notas (opcional):**
   * Campo de texto libre
   * Ejemplo: "Envío marítimo - Contenedor #ABC123", "Compra urgente vía aérea"

**Paso 2: Búsqueda y selección de productos**

1. **Búsqueda en tiempo real:**
   * Campo de búsqueda con autocompletado
   * Busca por: SKU, nombre del producto, marca
   * Búsqueda con debounce de 300ms (evita requests excesivos)
   * Muestra dropdown con resultados mientras se escribe

2. **Resultados de búsqueda:**
   * Cada producto muestra:
     * SKU (código único)
     * Nombre completo
     * Marca
     * Origen (país de fabricación)
     * Tipo (OEM o Aftermarket)
     * Stock actual (informativo, NO bloquea agregar)
   * **Importante:** A diferencia de ventas, en compras NO se valida stock porque justamente se está agregando stock nuevo

3. **Agregar producto:**
   * Click en un producto del dropdown → se agrega a la lista
   * Si el producto ya estaba agregado → incrementa cantidad en 1
   * El producto aparece en la lista de items con:
     * Información del producto (SKU, nombre, marca, origen)
     * Cantidad (editable, por defecto: 1)
     * Costo unitario (editable, por defecto: último costo conocido del producto)
     * Subtotal calculado automáticamente
     * Botón eliminar

4. **Editar items agregados:**
   * **Cantidad:** Input numérico inline, mínimo 1
     * Al cambiar: recalcula subtotal y total general
   * **Costo unitario:** Input numérico inline con decimales
     * Este costo puede variar por compra (diferente proveedor, momento, negociación)
     * Al cambiar: recalcula subtotal y total general
   * Los cálculos se actualizan en tiempo real sin hacer submit

**Paso 3: Resumen y confirmación**

El panel derecho (sticky) muestra:

1. **Total de la compra:**
   * Suma de todos los subtotales
   * Muestra en la moneda seleccionada (USD o ARS)
   * Si es USD con TC: también muestra conversión estimada a ARS

2. **Estadísticas:**
   * Cantidad de productos distintos
   * Cantidad total de unidades

3. **Validaciones:**
   * Botón "Registrar Compra" deshabilitado hasta que:
     * Haya al menos 1 producto agregado
     * Si moneda es USD, tenga tipo de cambio válido
     * Proveedor esté seleccionado

4. **Al confirmar (click en "Registrar Factura"):**

   El sistema ejecuta (vía `Purchasing::CreatePurchase` o `Invoices::CreateSimpleInvoice`):

   * **Validaciones:**
     * Proveedor existe
     * Todos los productos existen
     * Cantidades son > 0
     * Costos son >= 0
     * TC es > 0 si moneda es USD

   * **Si validaciones OK:**
     * Crea registro `Invoice` con:
       - Proveedor
       - Moneda (USD o ARS)
       - Tipo de cambio (si USD)
       - Fecha de compra
       - Total calculado
       - Notas
       - Status: 'confirmed'
     
     * Crea `InvoiceItem` por cada producto con:
       - Producto
       - Cantidad
       - Costo unitario (en la moneda de la compra)
     
     * Crea `StockMovement` positivos (entrada) por cada item:
       - Tipo: 'purchase'
       - Cantidad: positiva (entra stock)
       - Referencia: polimórfica a la compra
       - Ubicación: depósito principal
     
     * Actualiza stock automáticamente:
       - `current_stock` se incrementa vía callbacks de StockMovement
     
     * **Recalcula costo promedio ponderado:**
       - Para cada producto, calcula nuevo `cost_unit`:
         ```
         Todas las compras confirmadas → convertir a USD
         Promedio ponderado = SUM(cantidad × costo) / SUM(cantidad)
         ```
       - Guarda en `cost_unit` y `cost_currency = 'USD'`
       - Este costo promedio se usa para calcular márgenes y rentabilidad
     
     * Redirección a listado de compras con mensaje de éxito

   * **Si hay errores:**
     * Muestra mensaje de error en la parte superior del formulario
     * Mantiene el formulario con los datos ingresados
     * Usuario puede corregir y reintentar

**Ejemplo de compra típica:**

```
Proveedor: Toyota Japan Co
Moneda: USD
Tipo de cambio: 1,200.00
Fecha: 15/11/2024
Notas: Importación contenedor #CON123

Productos:
1. HDC001 - Filtro de Aceite Honda
   Cantidad: 50 unidades
   Costo unitario: $8.50 USD
   Subtotal: $425.00 USD

2. HDC015 - Pastillas de Freno Honda (OEM - Japan)
   Cantidad: 30 unidades
   Costo unitario: $25.00 USD
   Subtotal: $750.00 USD

Total: $1,175.00 USD
Equivalente en ARS: ~$1,410,000 (TC: 1,200)

Al confirmar:
- Se crea la compra con status 'confirmed'
- Stock de HDC001 aumenta +50
- Stock de HDC015 aumenta +30
- Costo promedio de cada producto se recalcula
```

**Diferencias clave vs Nueva Venta:**

| Aspecto | Nueva Venta | Nueva Compra |
|---------|-------------|--------------|
| **Validación stock** | ✅ Requiere stock disponible | ❌ No valida (es para agregar stock) |
| **Cliente/Proveedor** | Cliente (Mostrador o con CC) | Proveedor |
| **Precio/Costo** | Precio fijo del producto | **Costo editable** por item |
| **Moneda** | Siempre ARS | **USD o ARS** |
| **Tipo de cambio** | No aplica | **Requerido si USD** |
| **Movimiento stock** | Negativo (sale) | **Positivo (entra)** |
| **Actualización costos** | No | **Sí - recalcula promedio ponderado** |

**Notas importantes:**

* El costo unitario es editable por item porque:
  - Puede variar según negociación con proveedor
  - Puede haber descuentos por volumen en esa compra específica
  - Diferentes proveedores cobran precios distintos
  - El sistema usa estos costos para calcular el promedio ponderado

* El tipo de cambio se guarda con cada compra porque:
  - Permite trazabilidad histórica
  - El TC varía día a día
  - Necesario para calcular el costo real en ARS de esa compra específica
  - Usado para convertir costos ARS a USD en el cálculo del promedio

* El costo promedio ponderado permite:
  - Saber el costo "real" del inventario
  - Calcular márgenes de ganancia precisos
  - Tomar decisiones de precios informadas
  - Valuar correctamente el inventario

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

---

## 9. Ventas-Lite (Desde Talonarios Físicos)

### Contexto

Durante la transición de ventas en papel a sistema digital, se implementó un modo "ventas-lite" 
que prioriza el control de stock sobre la precisión financiera.

### Objetivo

- Registrar qué productos se vendieron y en qué cantidad (control de inventario)
- Mantener trazabilidad de ventas por producto/variante
- Permitir análisis de qué se vende más (OEM vs Aftermarket, orígenes)

### Campos Específicos

#### `source` (string)

Indica el origen de la venta:

- `'live'` (default): Venta registrada en tiempo real con precios de BD
- `'from_paper'`: Venta cargada desde talonario físico

#### `sale_date` (date)

Fecha REAL de la venta (puede diferir de `created_at` si se carga con retraso).

- Ejemplo: Venta del 16/12 cargada el 23/12
  - `sale_date`: 16/12/2024
  - `created_at`: 23/12/2024 10:30

#### `paper_number` (string, opcional)

Número del talonario físico para cruzar con registros en papel.

- Ejemplo: "0045", "0123"
- Permite match: "Venta sistema #234 = Talonario #0045"

### Reglas de Validación

#### Ventas Live (`source = 'live'`)

- `total_amount` DEBE ser > 0
- `unit_price` en items DEBE tener valor
- Precios vienen de la BD (confiables para reportes financieros)

#### Ventas From Paper (`source = 'from_paper'`)

- `total_amount` PUEDE ser >= 0 (incluso 0 si precios desconocidos)
- `unit_price` en items PUEDE ser nil o 0
- Precios son aproximados (NO usar para reportes financieros)

### Control de Stock

**AMBOS modos funcionan igual:**

- Validan stock disponible antes de crear venta
- Crean `StockMovement` de tipo `sale` (cantidad negativa)
- Actualizan `current_stock` del producto
- Pueden ser cancelados (reintegran stock)

### Flujo de Carga desde Talonario

1. Usuario accede a "Nueva Venta"

2. Completa campos:
   - **Fecha de venta**: Fecha real del talonario (default: hoy)
   - **N° Talonario**: Número impreso en el talonario físico
   - **Cliente**: "Cliente Mostrador" (default)
   - **Productos**: Busca y agrega productos vendidos
   - **Cantidad**: Unidades vendidas (obligatorio)
   - **Precio**: Precio de venta (editable, puede dejarse en 0 si desconocido)

3. Sistema valida stock disponible

4. Crea Order con:
   - `source = 'from_paper'`
   - `paper_number` del talonario
   - `sale_date` real de la venta
   - `total_amount` suma de items (puede ser 0)

5. Genera StockMovements de salida

6. Actualiza stock de productos

### Reportes y Métricas

#### Para Control de Stock (usar ambos modos)

```ruby
# Productos más vendidos
Order.includes(:order_items)
     .group('products.name')
     .sum('order_items.quantity')

# Ventas por variante
Product.where(product_type: 'oem').joins(:order_items).sum('order_items.quantity')
```

#### Para Reportes Financieros (usar SOLO live)

```ruby
# Ingresos reales
Order.live.sum(:total_amount)

# Márgenes
Order.live.includes(:order_items, :products).map(&:margin).sum
```

⚠️ **IMPORTANTE:** NO usar ventas `from_paper` para cálculos financieros. 
Los precios son aproximados y pueden ser cero.

### Evolución Futura

Cuando el sistema esté en uso diario:

1. Cambiar `source` default a `'live'`
2. Ventas se registran en tiempo real con precios de BD
3. Ventas `from_paper` pasan a ser históricas (para análisis de transición)

## 10. Autenticación y Autorización

### Roles de Usuario

El sistema tiene 3 roles de usuario con permisos diferenciados:

#### Vendedor

**Usuarios:** Alfredo, Ariel (personal de mostrador)

**Permisos:**

- ✅ Ver productos
- ✅ Crear ventas (cash y credit)
- ✅ Ver listado de ventas
- ✅ Ver detalle de ventas
- ❌ Cancelar ventas
- ❌ Ver reportes financieros
- ❌ Gestionar stock manualmente
- ❌ Crear/editar productos
- ❌ Crear compras
- ❌ Ver/registrar pagos

#### Caja

**Usuarios:** Mari (contabilidad/caja)

**Permisos:**

- ✅ Ver ventas
- ✅ Ver listado de pagos
- ✅ Registrar pagos de clientes
- ✅ Ver saldos de clientes
- ❌ Crear ventas
- ❌ Cancelar ventas
- ❌ Gestionar productos
- ❌ Gestionar stock
- ❌ Crear compras

#### Admin

**Usuarios:** Owner y socio

**Permisos:**

- ✅ Acceso completo a todas las funcionalidades
- ✅ Gestionar usuarios (crear, editar, eliminar vía consola)
- ✅ Ver todos los reportes
- ✅ Configuración del sistema
- ✅ Todas las acciones de vendedor y caja

### Gestión de Usuarios

Por ahora, los usuarios se crean/gestionan manualmente vía Rails console:

```ruby
# Crear usuario vendedor
User.create!(
  email: 'alfredo@gentedelsol.com',
  password: 'password123',
  name: 'Alfredo',
  role: 'vendedor'
)

# Crear usuario caja
User.create!(
  email: 'mari@gentedelsol.com',
  password: 'password123',
  name: 'Mari',
  role: 'caja'
)

# Cambiar rol de usuario
user = User.find_by(email: 'alfredo@gentedelsol.com')
user.update(role: 'admin')

# Cambiar contraseña
user.update(password: 'nueva_password', password_confirmation: 'nueva_password')
```

En el futuro se implementará ActiveAdmin para gestión visual de usuarios.

### Implementación Técnica

- **Autenticación:** Devise (database_authenticatable + trackable)
- **Autorización:** Pundit (policies por modelo)
- **Roles:** Enum simple (un usuario = un rol)
- **Tracking:** Se registra `last_sign_in_at` y `sign_in_count`

### Seguridad

- Passwords hasheados con bcrypt
- No hay auto-registro (solo admin crea usuarios)
- Sesiones expiradas requieren re-login
- Intentos de acceso no autorizado muestran mensaje y redirigen

## 11. Sincronización de Inventario desde Excel

### Contexto

El inventario se gestiona inicialmente en Excel. Para mantener el sistema actualizado, existe un script que sincroniza productos y stock desde archivo Excel.

### Comando

```bash
rails inventory:sync_from_excel['/path/to/archivo.xlsx']
```

### Funcionamiento

#### Productos Nuevos

1. Lee fila del Excel
2. Valida datos (stock >= 0, precio > 0, SKU presente)
3. Limpia SKU (quita sufijo `-IMP`)
4. Crea producto con:
   - `product_type = 'aftermarket'`
   - `origin` mapeado desde código (JAP/TAI/CHI)
   - `brand = NULL`, `category = NULL`
   - `current_stock = 0`
5. Si stock Excel > 0:
   - Crea `StockMovement` tipo `adjustment`
   - Cantidad = stock del Excel
   - Note = "Initial stock from Excel import"
   - Recalcula `current_stock`

#### Productos Existentes

1. Busca producto por SKU + `product_type = 'aftermarket'`
2. Si precio cambió: actualiza `price_unit`
3. Calcula diferencia: `diff = stock_excel - current_stock`
4. Si `diff != 0`:
   - Crea `StockMovement` tipo `adjustment`
   - Cantidad = diff (puede ser +/-)
   - Note = "Stock adjustment from Excel import"
   - Recalcula `current_stock`

### Validaciones

- **Stock:** No puede ser negativo
- **Precio:** Debe ser mayor a 0
- **SKU y Nombre:** Obligatorios
- **Errores:** No detienen el proceso, se registran y continúa

### Reglas de Negocio

#### SKU

- Todos los SKUs en Excel terminan en `-IMP` (importado/aftermarket)
- Se almacenan SIN el sufijo `-IMP` en la BD
- Ejemplo: `91503-SZ3-003-IMP` → se guarda como `91503-SZ3-003`

#### Origen

- `JAP` → `japan`
- `TAI` → `taiwan`
- `CHI` → `china`
- Otros códigos → `NULL`

#### Product Type

- Todos los productos del Excel son `aftermarket` (por tener sufijo `-IMP`)
- `product_type = 'aftermarket'`

#### Brand y Category

- Todos `NULL` por ahora (no hay columna de marca en Excel)
- Clasificación manual posterior

#### Precio y Costo

- `cost_unit` = Precio Lista (USD) del Excel
- `cost_currency` = 'USD'
- `price_unit` = Precio Venta (ARS) del Excel

### Logging

Cada ejecución genera un log detallado en:

```
log/inventory_sync_YYYY-MM-DD_HH-MM-SS.log
```

El log incluye:

- Timestamp de inicio/fin
- Cada producto procesado (creado/actualizado/error)
- Cambios realizados (precio, stock)
- Movimientos de stock generados
- Resumen final con estadísticas:
  - Productos creados
  - Productos actualizados
  - Productos sin cambios (skipped)
  - Errores encontrados
  - Movimientos de stock creados
  - Valor total del inventario

### Ejemplo de uso

```bash
# Sincronizar desde archivo específico
rails inventory:sync_from_excel['/path/to/productos.xlsx']

# Si el archivo está en tmp/productos.xlsx (valor por defecto)
rails inventory:sync_from_excel
```

### Output esperado

```
================================================================================
📊 INVENTORY SYNC FROM EXCEL
================================================================================
File: /path/to/productos.xlsx
Started at: 2025-12-26 10:30:00 -0300
================================================================================

📦 Procesando 150 productos...

✅ 91503-SZ3-003 → Creado
   📦 Stock inicial: 799
✅ 12342-P2F-A01 → Creado
   📦 Stock inicial: 160
🔄 91503-AAA-999 → Actualizado
   Price: $1.200 ARS → $1.300 ARS (+$100 ARS)
   Stock: 50 → 75 (+25 units)
⚠️  ERROR: 88888-XXX-000 → Stock cannot be negative (value: -10)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 RESUMEN:
  ✅ Productos creados: 120
  🔄 Productos actualizados: 25
  ⏭️  Productos sin cambios: 3
  ⚠️  Errores: 2
  📈 Stock Movements: 145
  
  📦 Total productos: 520
  📊 Stock total: 8,450 unidades
  💰 Valor inventario: $12.450.000 ARS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ Sincronización completada exitosamente
📄 Log guardado en: /path/to/simple_stock/log/inventory_sync_2025-12-26_10-30-00.log
```

### Consideraciones

- **Performance:** El proceso puede tardar varios minutos para archivos grandes (1000+ productos)
- **Transacciones:** Cada producto se procesa en su propia transacción para aislar errores
- **Idempotencia:** Se puede ejecutar múltiples veces de forma segura
- **Stock:** Los ajustes negativos son validados para evitar stock negativo
- **Auditoría:** Todos los cambios quedan registrados en `stock_movements`

### Evolución futura

Posibles mejoras para V2:

- Sincronización automática programada (cron job)
- Upload de Excel desde la UI web
- Preview de cambios antes de aplicar
- Soporte para actualizar `brand` y `category`
- Validación de duplicados por `(sku, product_type, brand, origin)`
- Notificaciones por email al completar
- Rollback de sincronizaciones anteriores

---

## 12. Compras - Modo Simple vs Modo Completo

### Contexto

El modelo Invoice soporta dos modos de operación según el flag `has_items`:

### Modo Simple (has_items: false)

**Propósito:** Registrar facturas de proveedores sin detalle de productos (para HOY)

**Campos principales:**
- `supplier_id`: Proveedor que emitió la factura
- `invoice_number`: Número de factura del proveedor
- `amount`: Monto total de la factura
- `currency`: USD o ARS
- `exchange_rate`: Tipo de cambio (si USD)
- `purchase_date`: Fecha de emisión de la factura
- `due_date`: Fecha de vencimiento de pago
- `status`: pending/paid
- `paid_at`: Fecha de pago (cuando se marca como pagada)

**Características:**
- NO tiene `invoice_items` asociados
- NO genera `stock_movements`
- NO recalcula costos promedio de productos
- Se usa para control de cuentas a pagar
- Permite marcar como "pagada" con fecha

**Uso:**
```ruby
Invoices::CreateSimpleInvoice.call(
  supplier: supplier,
  invoice_number: 'FAC-001',
  amount: 5000,
  currency: 'USD',
  exchange_rate: 1200,
  purchase_date: Date.today,
  due_date: 30.days.from_now,
  notes: 'Factura IPC'
)
```

### Modo Completo (has_items: true)

**Propósito:** Registrar compras con detalle de productos (para DESPUÉS)

**Campos principales:**
- `supplier_id`: Proveedor
- `currency`: USD o ARS
- `exchange_rate`: Tipo de cambio
- `purchase_date`: Fecha de compra
- `status`: confirmed/cancelled
- `invoice_items`: Detalle de productos comprados

**Características:**
- SÍ tiene `invoice_items` asociados (obligatorio)
- SÍ genera `stock_movements` de entrada
- SÍ recalcula costos promedio ponderado
- Se usa para gestión de inventario
- No se "paga" (concepto diferente)

**Uso:**
```ruby
Purchasing::CreatePurchase.call(
  supplier: supplier,
  items: [
    { product_id: 1, quantity: 10, unit_cost: 50 },
    { product_id: 2, quantity: 5, unit_cost: 100 }
  ],
  currency: 'USD',
  exchange_rate: 1200,
  purchase_date: Date.today
)
```

### Comparación

| Característica | Modo Simple | Modo Completo |
|---|---|---|
| `has_items` | false | true |
| Estado inicial | pending | confirmed |
| `purchase_items` | No | Sí (obligatorio) |
| `stock_movements` | No | Sí |
| Recalcula costos | No | Sí |
| Campo `amount` | Obligatorio | No usado |
| Campo `due_date` | Obligatorio | No usado |
| Se puede "pagar" | Sí | No |

### Evolución Futura

Cuando se tenga el inventario completo, se puede:

1. Crear Invoice en modo completo (has_items: true)
2. Opcionalmente vincular con factura en modo simple existente
3. El modo simple queda para facturas históricas o sin detalle

### Estados de Invoice

**Para Modo Simple:**
- `pending`: Factura pendiente de pago
- `paid`: Factura pagada (con `paid_at` registrado)

**Para Modo Completo:**
- `confirmed`: Compra confirmada, stock actualizado
- `cancelled`: Compra cancelada, stock revertido

### Marcar Factura como Pagada

Solo aplica a invoices en modo simple:

```ruby
invoice = Invoice.find(123)
Invoices::MarkAsPaid.call(
  invoice: invoice,
  payment_date: Date.today
)
```

Esto:
1. Cambia status de `pending` → `paid`
2. Registra `paid_at` con la fecha de pago
3. NO genera movimientos contables (se hace en otro módulo)

### Scopes Útiles

```ruby
# Facturas simples pendientes de pago
Invoice.simple_mode.pending_payment

# Facturas vencidas
Invoice.overdue

# Facturas con vencimiento próximo (7 días)
Invoice.due_soon

# Facturas ya pagadas
Invoice.paid_invoices

# Compras completas confirmadas
Invoice.full_mode.confirmed_status
```

### Ejemplo de Uso Típico - Modo Simple

**Escenario:** Llega factura de IPC (proveedor) por $5,000 USD, vence en 30 días.

```ruby
# 1. Buscar o crear proveedor
supplier = Supplier.find_by(name: 'IPC') || 
           Supplier.create!(name: 'IPC', contact_name: 'Juan Pérez')

# 2. Registrar factura
result = Invoices::CreateSimpleInvoice.call(
  supplier: supplier,
  invoice_number: 'IPC-2024-001',
  amount: 5000,
  currency: 'USD',
  exchange_rate: 1200,
  purchase_date: Date.today,
  due_date: 30.days.from_now,
  notes: 'Factura mensual de repuestos'
)

if result.success?
  puts "Factura registrada: #{result.record.invoice_number}"
  puts "Monto: $#{result.record.amount} #{result.record.currency}"
  puts "Vence: #{result.record.due_date}"
else
  puts "Error: #{result.errors.join(', ')}"
end

# 3. Consultar facturas pendientes
pending = Invoice.simple_mode.pending_payment.order(:due_date)
pending.each do |invoice|
  puts "#{invoice.invoice_number} - $#{invoice.amount} - Vence: #{invoice.due_date}"
end

# 4. Al pagar la factura
invoice = Invoice.find_by(invoice_number: 'IPC-2024-001')
result = Invoices::MarkAsPaid.call(
  invoice: invoice,
  payment_date: Date.today
)

if result.success?
  puts "Factura marcada como pagada"
else
  puts "Error: #{result.errors.join(', ')}"
end
```

### Migración de Datos Existentes

Al ejecutar la migration que renombró `purchases` a `invoices`, todas las compras existentes se marcan automáticamente como `has_items: true` (modo completo), preservando el comportamiento actual del sistema.

---

## 13. Proveedores

### Campos del Modelo

- `name` (obligatorio, único) - Nombre del proveedor
- `email` (opcional) - Email de contacto
- `phone` (opcional) - Teléfono
- `cuit` (opcional) - CUIT sin validación de formato
- `bank_alias` (opcional) - Alias CBU
- `bank_account` (opcional) - Número de cuenta/CBU
- `payment_term_days` (opcional) - Días de gracia para pago

### Reglas de Negocio

1. **Nombre único:** No puede haber proveedores duplicados
2. **Nombre no editable:** Una vez creado, el nombre no se puede cambiar
3. **Otros campos editables:** Email, teléfono, CUIT, datos bancarios y plazo pueden editarse
4. **Eliminación restringida:** No se puede eliminar si tiene facturas (purchases) asociadas
5. **Payment term days:** Define los días de gracia que otorga el proveedor para pago
6. **Solo administradores:** Solo usuarios con rol admin pueden gestionar proveedores

### Uso del Payment Term Days

El campo `payment_term_days` se usa para calcular automáticamente la fecha de vencimiento (`due_date`) al crear facturas:

```ruby
# Ejemplo:
# Proveedor "IPC" tiene payment_term_days: 30
# Factura creada el 14/01/2026
# due_date = 14/01/2026 + 30 días = 13/02/2026
```

Este cálculo se hará manualmente por ahora. En el futuro se puede implementar con JavaScript/Stimulus.

### Permisos (Pundit)

Solo usuarios **admin** pueden:
- Ver lista de proveedores
- Ver detalle de proveedor
- Crear nuevos proveedores
- Editar proveedores (excepto nombre)
- Eliminar proveedores (solo si no tienen facturas)

### Vistas

#### Index (`/web/suppliers`)
- Lista alfabética de todos los proveedores
- Muestra nombre, email, teléfono y plazo de pago
- Card clicable que lleva al detalle
- Botón "Nuevo Proveedor" (solo admin)

#### Show (`/web/suppliers/:id`)
- Información completa del proveedor
- Datos bancarios si están disponibles
- Lista de facturas pendientes (con alertas de vencimiento)
- Últimas 10 facturas pagadas
- Resumen: total de facturas pendientes y monto adeudado
- Botones: Editar y Eliminar (si no tiene facturas)

#### New (`/web/suppliers/new`)
- Formulario de creación
- Secciones: Información Básica, Información Bancaria, Condiciones de Pago
- Nombre obligatorio (advertencia: no editable después)
- Todos los demás campos opcionales

#### Edit (`/web/suppliers/:id/edit`)
- Formulario de edición
- Nombre en campo readonly (no editable)
- Todos los demás campos editables

### Métodos Helper del Modelo

**`bank_info_present?`**
- Retorna true si tiene alias o cuenta bancaria

**`bank_info_formatted`**
- Retorna string formateado con información bancaria
- Ej: "Alias: MI.ALIAS.CBU | Cuenta: 0170000040000012345678"

**`total_pending_amount`**
- Retorna el total adeudado en ARS de todas las facturas pendientes
- Convierte USD a ARS automáticamente

**`pending_invoices_count`**
- Retorna cantidad de facturas pendientes de pago

**`payment_term_display`**
- Retorna "30 días" o "No definido"

### Ejemplo de Uso

```ruby
# Crear proveedor
supplier = Supplier.create!(
  name: "IPC",
  email: "ventas@ipc.com.ar",
  phone: "11-4567-8901",
  cuit: "30-12345678-9",
  bank_alias: "IPC.REPUESTOS",
  payment_term_days: 30
)

# Consultar información
supplier.payment_term_display  # => "30 días"
supplier.total_pending_amount   # => 1500000 (ARS)
supplier.pending_invoices_count # => 3

# Crear factura para este proveedor
invoice = Invoices::CreateSimpleInvoice.call(
  supplier: supplier,
  invoice_number: "FAC-001",
  amount: 5000,
  currency: "USD",
  exchange_rate: 1200,
  purchase_date: Date.today,
  due_date: Date.today + supplier.payment_term_days.days  # Auto-calcula vencimiento
)
```

### Relación con Facturas (Invoices)

- Un proveedor puede tener muchas facturas (has_many :invoices)
- No se puede eliminar un proveedor si tiene facturas asociadas
- En la vista show se muestran facturas pendientes y pagadas
- El total adeudado se calcula sumando facturas pendientes en ARS

---

## 14. Notas de Crédito

### Contexto

Las notas de crédito (CreditNote) son documentos que los proveedores emiten al negocio para acreditar montos por devoluciones, errores de facturación, descuentos retroactivos, o cualquier otro concepto que reduzca el balance adeudado.

### Características Principales

**Reglas de Negocio:**

1. Una NC puede estar asociada a una factura específica (opcional)
2. Si tiene factura asociada → hereda moneda y tipo de cambio de esa factura automáticamente
3. Si NO tiene factura asociada → moneda por defecto ARS
4. Las NC restan automáticamente del balance del proveedor
5. Las NC se pueden editar después de creadas
6. Las NC pueden tener productos asociados (opcional, para futuro manejo de inventario)
7. Solo usuarios admin pueden eliminar notas de crédito

### Modelo de Datos

**Campos de CreditNote:**

- `supplier_id` - Proveedor que emitió la NC (obligatorio)
- `invoice_id` - Factura relacionada (opcional)
- `credit_note_number` - Número de la NC (único, obligatorio)
- `amount` - Monto de la NC (obligatorio, > 0)
- `currency` - Moneda: USD o ARS (obligatorio, default: ARS)
- `exchange_rate` - Tipo de cambio (obligatorio si USD)
- `issue_date` - Fecha de emisión (obligatorio)
- `notes` - Notas adicionales (opcional)

**Relaciones:**

- `belongs_to :supplier`
- `belongs_to :invoice` (opcional)
- `has_many :credit_note_items` (para futuro)
- `has_many :products` (through credit_note_items)

### Cálculo de Balance del Proveedor

El balance neto de un proveedor se calcula como:

```
Balance Neto = Total Facturas Pendientes - Total Notas de Crédito
```

**Ejemplo:**

```
Facturas pendientes:
- FAC-001: $1000 USD × 1200 = $1,200,000 ARS
- FAC-002: $500,000 ARS
Total facturas: $1,700,000 ARS

Notas de crédito:
- NC-001: $200 USD × 1200 = $240,000 ARS
- NC-002: $100,000 ARS
Total créditos: $340,000 ARS

Balance neto: $1,700,000 - $340,000 = $1,360,000 ARS
```

### Métodos del Modelo Supplier

**`total_credit_notes_amount`**
- Retorna el total de créditos en ARS
- Convierte USD a ARS automáticamente

**`credit_notes_count`**
- Retorna cantidad de notas de crédito

**`current_balance`**
- Retorna el balance neto (facturas - créditos) en ARS
- Puede ser negativo si los créditos superan las facturas (a favor del negocio)

### Flujo de Uso

#### Crear Nota de Crédito Sin Factura Asociada

**Escenario:** El proveedor IPC envía NC-2024-001 por $100,000 ARS por error de facturación.

```ruby
supplier = Supplier.find_by(name: "IPC")

credit_note = CreditNote.create!(
  supplier: supplier,
  credit_note_number: "NC-2024-001",
  amount: 100000,
  currency: "ARS",
  issue_date: Date.today,
  notes: "Error de facturación en diciembre"
)
```

#### Crear Nota de Crédito Asociada a Factura

**Escenario:** Devolución de mercadería de la factura FAC-001 (USD).

```ruby
invoice = Invoice.find_by(invoice_number: "FAC-001")

credit_note = CreditNote.new(
  supplier: invoice.supplier,
  invoice: invoice,  # Hereda currency y exchange_rate automáticamente
  credit_note_number: "NC-2024-002",
  amount: 500,       # $500 USD
  issue_date: Date.today,
  notes: "Devolución de 10 filtros defectuosos"
)

credit_note.save!

# La NC hereda:
# - currency: "USD"
# - exchange_rate: (el de la factura)
```

### Consultas Útiles

```ruby
# Todas las NCs de un proveedor
supplier.credit_notes

# Total de créditos
supplier.total_credit_notes_amount  # En ARS

# Balance neto (facturas - créditos)
supplier.current_balance  # En ARS

# NCs recientes
CreditNote.recent.limit(10)

# NCs de un proveedor específico
CreditNote.for_supplier(supplier)

# Buscar por número
CreditNote.search_number("NC-2024")
```

### Vistas del Sistema

**Index (`/web/credit_notes`)**
- Lista de todas las notas de crédito
- Filtros: Proveedor, Búsqueda por número
- Métrica: Crédito total en ARS
- Tabla con: Fecha, Proveedor, N° NC, Factura ref, Monto
- Acciones: Ver, Editar

**Show (`/web/credit_notes/:id`)**
- Detalle completo de la NC
- Información del proveedor (con link)
- Información de factura asociada (con link, si existe)
- Conversión a ARS si es USD
- Botones: Editar, Eliminar (solo admin), Volver

**New (`/web/credit_notes/new`)**
- Formulario de creación
- Si viene con `?invoice_id=X`, pre-carga la factura y hereda sus datos
- Moneda readonly si tiene factura asociada
- Tipo de cambio se muestra/oculta según moneda

**Edit (`/web/credit_notes/:id/edit`)**
- Formulario de edición
- Todos los campos editables

### Permisos (Pundit)

- **index/show/create/update**: Todos los usuarios autenticados
- **destroy**: Solo usuarios admin

### Casos de Uso Comunes

#### 1. Devolución de Mercadería

Proveedor acepta devolución de productos defectuosos y emite NC.

1. Usuario accede a la factura original
2. Click en "Crear Nota de Crédito" (futuro botón)
3. Sistema pre-carga: proveedor, factura, moneda, TC
4. Usuario ingresa: N° NC, monto, fecha, motivo
5. Sistema registra NC y actualiza balance

#### 2. Error de Facturación

Proveedor emitió factura incorrecta y envía NC correctora.

1. Usuario accede a Notas de Crédito → Nueva
2. Selecciona proveedor
3. Opcionalmente selecciona factura relacionada
4. Ingresa datos de la NC
5. Sistema registra y actualiza balance

#### 3. Descuento Retroactivo

Proveedor otorga descuento por volumen acumulado.

1. Usuario crea NC sin factura asociada
2. Moneda: ARS (por defecto)
3. Ingresa monto del descuento
4. Sistema registra y reduce balance adeudado

### Evolución Futura

**V2 - Gestión de Items:**
- Permitir agregar productos específicos a las NC
- Calcular monto automáticamente desde items
- Trazabilidad: qué productos se devolvieron

**V2 - Stock:**
- NCs con productos podrían generar StockMovement negativos
- Integración con inventario para devoluciones

**V2 - Automatización:**
- Crear NC directamente desde vista de factura
- Sugerir monto basado en items de la factura
- Validar que NC no supere monto de factura asociada
