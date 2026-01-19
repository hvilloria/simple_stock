# DEVELOPMENT_GUIDE.md

**Guía de Desarrollo - Sistema de Gestión de Repuestos de Autos**

Reglas, principios y convenciones para este proyecto Rails.

**Stack Técnico:**
- Ruby on Rails 7+
- PostgreSQL
- Hotwire (Turbo + Stimulus)
- HAML para vistas
- TailwindCSS (via tailwindcss-rails)
- Services para casos de uso

**Objetivo:** Que humanos y agentes de IA (Cursor, Claude, ChatGPT) generen código integrable de inmediato, consistente con la arquitectura y las reglas de negocio.

---

## 1. CONTEXTO DEL PROYECTO

### 1.1. Descripción del Negocio

- **Negocio:** Gente del Sol - Venta de repuestos de autos Honda
- **Ubicación:** Av. Warnes 620, CABA, Buenos Aires, Argentina
- **Especialidad:** Repuestos Honda originales y alternativos de calidad
- **Trayectoria:** 35+ años en el mercado
- **Tipo:** Un solo local físico (no es cadena)

### 1.2. Módulos del Sistema

1. **Productos / Inventario:** Catálogo, códigos, categorías, precios
2. **Movimientos de Stock:** Control basado en movimientos, trazabilidad
3. **Ventas:** Mostrador (contado) y cuenta corriente, múltiples canales
4. **Clientes:** Cliente Mostrador genérico + clientes con cuenta corriente
5. **Pagos / Cobranzas:** Pagos globales, control de saldos
6. **Compras:** Registro en USD, conversión a ARS

### 1.3. Alcance de V1

**✅ Incluye:**
- Gestión completa de productos
- Control de stock por movimientos
- Ventas de contado y a crédito
- Cuentas corrientes de clientes
- Registro de pagos globales
- Compras en USD con tipo de cambio
- Ajustes de stock manual
- Anulación de ventas
- Dashboard con métricas básicas

**❌ NO incluye (futuro):**
- Manejo de chasis/VIN de vehículos
- Integración automática con Mercado Libre
- Courier/flete en costos
- Matching de pagos a ventas específicas
- Notas de crédito detalladas
- Devoluciones parciales

**Documentos relacionados:**
- `FLUJOS.md` - Especificación funcional completa
- `UI_DESIGN_SPEC.md` - Diseño de interfaces
- `CODE_PATTERNS.md` - Ejemplos de código y patrones

---

## 2. ARQUITECTURA DEL PROYECTO

### 2.1. Estructura de Carpetas

```
app/
  controllers/
    application_controller.rb
    web/                          # Namespace principal
      dashboard_controller.rb
      products_controller.rb
      orders_controller.rb
      customers_controller.rb
      payments_controller.rb
      invoices_controller.rb
      stock_movements_controller.rb

  models/                         # Active Record models
    product.rb
    order.rb                      # Venta/Sale
    order_item.rb
    stock_movement.rb
    customer.rb
    payment.rb
    invoice.rb                    # Factura de proveedor
    invoice_item.rb
    supplier.rb
    exchange_rate.rb
    user.rb

  services/                       # Casos de uso
    inventory/
      adjust_stock.rb
      calculate_stock_level.rb
    sales/
      create_order.rb
      cancel_order.rb
    payments/
      register_payment.rb
    purchasing/
      create_purchase.rb

  views/
    layouts/
      application.html.haml
      web/
        _sidebar.html.haml
        _header.html.haml
    shared/
      ui/                         # Componentes UI reutilizables
        _button.html.haml
        _card.html.haml
        _badge.html.haml
        _modal.html.haml
    web/
      dashboard/
        index.html.haml
      products/
        index.html.haml
        new.html.haml
        edit.html.haml
        show.html.haml
        _form.html.haml
      orders/
      customers/
      payments/
      invoices/
      stock_movements/

  javascript/
    controllers/                  # Stimulus controllers
      search_controller.js
      modal_controller.js
      autocomplete_controller.js

config/
  routes.rb
  database.yml
  tailwind.config.js

db/
  migrate/
  seeds.rb

spec/                            # o test/ si usás Minitest
  models/
  services/
  requests/
  system/
```

### 2.1.1. Modelos Principales Implementados

**Productos e Inventario:**
- `Product` - Productos con SKU, precios, costos, origen, tipo (OEM/aftermarket)
- `StockMovement` - Movimientos de stock (con reference polimórfico)
- `StockLocation` - Ubicaciones de stock

**Ventas:**
- `Order` - Ventas/Órdenes (cash o credit)
- `OrderItem` - Items de cada venta

**Clientes y Pagos:**
- `Customer` - Clientes (con/sin cuenta corriente)
- `Payment` - Pagos de cuenta corriente

**Compras:**
- `Invoice` - Facturas de proveedores (USD o ARS)
- `InvoiceItem` - Items de cada factura
- `Supplier` - Proveedores

**Usuarios:**
- `User` - Usuarios del sistema (pendiente autenticación)

---

### 2.2. Responsabilidades de Cada Capa

#### Models (app/models)

**Representan:** Conceptos del negocio

**✅ Deben contener:**
- Asociaciones (`belongs_to`, `has_many`)
- Validaciones de datos
- Métodos de cálculo simples (totales, márgenes)
- Scopes para queries comunes
- Callbacks simples (solo si son necesarios)

**❌ NO deben contener:**
- Lógica relacionada a HTTP (params, request, response)
- Lógica de vistas o presentación
- Coordinación compleja entre múltiples modelos
- Transacciones complejas

#### Services (app/services)

**Representan:** Casos de uso que orquestan varios modelos

**Estructura:** `app/services/[dominio]/[accion].rb`

**✅ Responsabilidades:**
- Abrir transacciones de base de datos
- Crear/actualizar varios modelos coordinadamente
- Aplicar reglas de negocio complejas
- Crear StockMovement cuando corresponda
- Devolver resultado claro y consistente

**Patrón de resultado:**
```ruby
Result = Struct.new(:success?, :record, :errors, keyword_init: true)
```

**Cuándo crear un service:**
- La operación afecta múltiples modelos
- Hay lógica de coordinación compleja
- Se requiere una transacción
- La operación tiene múltiples pasos

#### Controllers (app/controllers)

**Principio:** "Thin controllers" - controladores delgados

**✅ Responsabilidades:**
- Recibir y validar params
- Llamar al service o modelo correspondiente
- Decidir redirect_to, render, o respuesta Turbo
- Manejar autenticación y autorización
- Setear variables de instancia para vistas

**❌ NO deben contener:**
- Reglas de negocio complejas
- Coordinación entre múltiples modelos
- Cálculos complejos
- Creación manual de múltiples registros

#### Views (app/views/web/)

**Formato:** HAML + TailwindCSS

**✅ Contienen:**
- Lógica de presentación (qué mostrar)
- Mensajes de error y éxito
- Form helpers
- Iteraciones sobre colecciones
- Uso de partials

**❌ NO deben contener:**
- Lógica de negocio
- Queries a base de datos
- Cálculos complejos

---

## 3. REGLAS DE NEGOCIO OBLIGATORIAS

> Para detalle completo, consultar `FLUJOS.md`

### 3.1. Stock

**Regla fundamental:** El stock NUNCA se edita directamente en el modelo Product

- ✅ Correcto: Crear StockMovement
- ❌ Incorrecto: `product.update(stock: X)`

**Reglas:**
1. No se permite stock negativo
2. Stock actual = suma de todos los movimientos
3. Tipos de movimiento: `purchase`, `sale`, `adjustment`
4. Validar stock disponible ANTES de crear ventas

### 3.2. Clientes

**Dos tipos:**

1. **Cliente Mostrador (genérico)**
   - Único, creado en seeds
   - Representa consumidores finales
   - Todas las ventas de contado van aquí
   - NO se registran individuales

2. **Clientes con cuenta corriente**
   - Talleres, mecánicos, empresas
   - Se registran individualmente
   - Tienen saldo
   - Pueden comprar a crédito

### 3.3. Ventas / Órdenes

**Tipos de venta:**

1. **Contado** (`cash`)
   - No genera saldo
   - No crea Payment

2. **Cuenta Corriente** (`credit`)
   - Genera saldo para el cliente
   - Solo para clientes registrados
   - Se paga luego con Payment

**Estados:**
- `confirmed`: venta confirmada
- `cancelled`: venta anulada

**Canales:**
- `counter`: mostrador
- `whatsapp`: WhatsApp
- `mercadolibre`: Mercado Libre (manual)

**Al confirmar venta:**
1. Validar stock disponible para cada producto
2. Crear la orden/venta
3. Crear items de la venta
4. Crear movimientos de stock NEGATIVOS

### 3.4. Anulación de Ventas

**En V1:** Solo anulación completa

**Proceso:**
1. Cambiar status a `cancelled`
2. Crear movimientos de stock INVERSOS (positivos)
3. El saldo del cliente se recalcula automáticamente

**Ventas anuladas NO cuentan para el saldo**

**Para corregir una venta:**
1. Anular la original
2. Crear una nueva venta correcta

### 3.5. Pagos y Saldos

**Payment:**
- Se asocia al cliente, NO a una venta específica
- Es un pago global (no hay matching en V1)
- Reduce el saldo del cliente

**Cálculo de saldo:**
```
saldo = SUM(ventas_activas_a_credito.total) - SUM(pagos.amount)
```

**Métodos de pago:**
- `cash`: Efectivo
- `transfer`: Transferencia
- `check`: Cheque

**Anulación de pagos:**
- Si error de carga: borrar el pago
- No se modela anulación formal en V1

### 3.6 Compras / Invoices

**Tipos de moneda:**

1. **USD** (dólares)
   - Requiere tipo de cambio (exchange_rate)
   - Se convierte a ARS para cálculos

2. **ARS** (pesos argentinos)
   - No requiere tipo de cambio

**Campos clave:**
- `supplier`: proveedor
- `currency`: 'USD' o 'ARS'
- `exchange_rate`: tipo de cambio si es USD
- `purchase_date`: fecha de la compra
- `status`: 'confirmed' o 'cancelled'

**Al confirmar compra:**
1. Crear invoice y invoice_items
2. Crear movimientos de stock POSITIVOS
3. **Recalcular costo promedio** de cada producto

**Costo Promedio Ponderado:**

El `cost_unit` del producto NO es el "último costo", sino el **costo promedio ponderado** de todas las compras confirmadas.

**Ejemplo:**
```
Compra 1: 5 pastillas @ $10 USD = $50 USD total
Compra 2: 5 pastillas @ $20 USD = $100 USD total
────────────────────────────────────────────────
Total: 10 pastillas por $150 USD
Costo promedio: $150 / 10 = $15 USD por unidad
```

**Se recalcula automáticamente:**
- Al confirmar una compra nueva
- Al anular una compra existente

**Método en Product:**
```ruby
product.recalculate_average_cost!
```

Este método:
1. Obtiene TODAS las compras confirmadas del producto
2. Convierte todo a USD para uniformidad
3. Calcula promedio ponderado: `total_costo_usd / total_cantidad`
4. Actualiza `cost_unit` y `cost_currency`

---

### 3.7. Tipo de Cambio

- Compras nuevas usan tipo de cambio actual
- Compras antiguas mantienen su tipo histórico
- Actualización manual por administrador

### 3.8. Chasis/VIN

**NO en V1:** El sistema no maneja chasis ni VIN

- Compatibilidad se determina fuera del sistema
- Vendedor usa herramientas externas
- Sistema solo registra la venta del producto

---

### 3.9. Reference Polimórfico en StockMovement

**Problema resuelto:**

Antes, `reference` era un string como `"ORDER-123"`. Esto no permitía queries eficientes ni integridad referencial.

**Solución: Reference polimórfico**

```ruby
# StockMovement ahora tiene:
t.string :reference_type   # 'Order', 'Invoice', NULL
t.integer :reference_id    # 123, 456, NULL
```

**Ventajas:**
1. Trazabilidad completa: `movement.reference` devuelve el objeto Order o Invoice
2. Queries eficientes: `order.stock_movements` funciona automáticamente
3. Integridad referencial

**Uso:**
```ruby
# Al crear movimiento
StockMovement.create!(
  product: product,
  quantity: -5,
  reference: order  # Rails guarda reference_type='Order', reference_id=order.id
)

# Consultas
order.stock_movements         # Todos los movements de esta orden
invoice.stock_movements       # Todos los movements de esta compra
movement.reference            # Devuelve Order o Invoice
```

**Casos de uso:**
- **Ventas**: `reference` apunta a Order
- **Compras**: `reference` apunta a Invoice
- **Ajustes manuales**: `reference` es NULL

---

### 4.0. Services - Método de Clase `.call`

**Patrón obligatorio:**

TODOS los services deben tener un método de clase `.call` que instancia y ejecuta.

**❌ Incorrecto:**
```ruby
service = Sales::CreateOrder.new(params)
result = service.call
```

**✅ Correcto:**
```ruby
result = Sales::CreateOrder.call(params)
```

**Implementación:**
```ruby
module Sales
  class CreateOrder
    # Método de clase
    def self.call(**params)
      new(**params).call
    end

    def initialize(**params)
      @param1 = params[:param1]
      # ...
    end

    def call
      # lógica del service
    end
  end
end
```

**Razón:**
- Más conciso
- Interfaz consistente
- Oculta detalles de instanciación

---

### 4.1. Costo Promedio - Cuándo Recalcular

**SIEMPRE recalcular `cost_unit` después de:**

1. Confirmar una compra nueva
   ```ruby
   # En Purchasing::CreatePurchase
   @invoice.invoice_items.each do |item|
     item.product.recalculate_average_cost!
   end
   ```

2. Anular una compra existente
   ```ruby
   # En Purchasing::CancelPurchase
   @invoice.invoice_items.each do |item|
     item.product.recalculate_average_cost!
   end
   ```

**NUNCA:**
- Editar `cost_unit` manualmente
- Asumir que `cost_unit` es el "último costo"
- Usar `cost_unit` sin considerar `cost_currency`

**Para reportes de margen:**
```ruby
# Margen de una venta
order_item.unit_price - product.cost_in_ars(exchange_rate)

# Margen sugerido del producto
product.margin(exchange_rate)
```

---

## 4. HOTWIRE, HAML Y TAILWIND

### 4.1. Hotwire (Turbo + Stimulus)

**Filosofía:** Dashboard interno clásico, NO una SPA

#### Turbo

**Usar para:**
- Navegación rápida (Turbo Drive - default)
- Formularios CRUD (Turbo Forms)
- Actualizaciones parciales (Turbo Frames)
- Updates en tiempo real (Turbo Streams)

**Evitar:**
- Complejidad innecesaria
- Cuando recarga completa es más simple

#### Stimulus

**Usar para:**
- Búsqueda en vivo (con debounce)
- Filtros dinámicos
- Modales y dropdowns
- Autocomplete
- Validaciones en cliente

**Evitar:**
- SPA compleja con Stimulus
- Lógica de negocio en JavaScript
- Reimplementar lo que Turbo ya hace

### 4.2. HAML

**Todas las vistas nuevas en HAML** (`app/views/web/`)

**Principios:**
- Solo lógica de presentación
- Reutilizar partials
- Mantener vistas simples y legibles
- Usar helpers para lógica repetitiva

### 4.3. TailwindCSS

**Configuración:** `tailwind.config.js` con design system

**Uso:**
- Clases Tailwind directamente en vistas
- Para patrones repetitivos: extraer a partials
- Componentes UI en `app/views/shared/ui/`

**Basado en UI_DESIGN_SPEC.md:**
- Color primario: `#1a9b8e` (teal)
- Espaciado: múltiplos de 4px
- Border radius: 6px, 8px, 12px
- Sombras: sm, md, lg, xl

---

## 5. WORKFLOWS DE DESARROLLO

### 5.1. Crear un Caso de Uso (Service)

**Pasos:**

1. Revisar reglas en `FLUJOS.md`
2. Crear service en `app/services/[area]/[accion].rb`
3. Implementar lógica:
   - Recibir parámetros claros
   - Abrir transacción
   - Crear/actualizar modelos
   - Aplicar reglas de negocio
   - Devolver Result
4. Usar desde controller
5. Agregar tests

**Ver ejemplos en:** `CODE_PATTERNS.md`

### 5.2. Implementar Pantalla CRUD

**Pasos:**

1. Definir rutas en `config/routes.rb`
2. Implementar acciones en controller
   - Si es complejo → service
3. Crear vistas HAML en `app/views/web/[resource]/`
   - Seguir diseño de `UI_DESIGN_SPEC.md`
   - Usar TailwindCSS
4. Reutilizar partials

### 5.3. Cambio en Reglas de Negocio

**Pasos:**

1. Revisar `FLUJOS.md`
2. Cambiar lógica en models/services (NO en controllers)
3. Ajustar controllers y vistas mínimamente
4. Actualizar/crear tests

---

## 6. ESTILO DE CÓDIGO Y TESTS

### 6.1. Convenciones

**Idioma:**
- Código (clases, métodos, variables, comentarios, mensajes de error): **inglés**
- Tests (describe, it, let): **inglés**
- Commits: **inglés**
- Textos visibles al usuario (flash messages, labels, emails): **español (voseo neutral)**

**Ejemplos:**

```ruby
# ✅ BIEN - Código en inglés
class Sales::CreateOrder
  def call
    validate_stock_availability
    create_order
  end
  
  private
  
  def validate_stock_availability
    # ...
  end
end

# ❌ MAL - Código en español
class Ventas::CrearOrden
  def llamar
    validar_disponibilidad_stock
  end
end
```

```ruby
# ✅ BIEN - Tests en inglés
RSpec.describe Product do
  it 'calculates stock from movements' do
    expect(product.current_stock).to eq(50)
  end
end

# ❌ MAL - Tests en español
RSpec.describe Product do
  it 'calcula el stock desde movimientos' do
    expect(product.current_stock).to eq(50)
  end
end
```

```ruby
# ✅ BIEN - Flash messages en español
redirect_to @order, notice: "Venta registrada exitosamente"

# ✅ BIEN - Labels en español (en vistas)
= f.label :name, "Nombre del producto"
```

**Estilo:**
- Métodos cortos y legibles
- Nombres descriptivos
- Evitar duplicación
- Comentarios solo cuando es necesario (preferir código auto-explicativo)

---

### 6.1.1. Testing de Services de Invoice

**Casos críticos a testear:**

```ruby
RSpec.describe Purchasing::CreatePurchase do
  # 1. Creación exitosa
  it 'creates invoice and increases stock'
  
  # 2. Actualización de costo promedio
  it 'recalculates product average cost after invoice'
  
  # 3. Múltiples compras
  it 'calculates weighted average from multiple invoices'
  
  # 4. Validaciones
  it 'requires exchange_rate for USD invoices'
  it 'validates currency is USD or ARS'
  
  # 5. Reference polimórfico
  it 'creates stock movements with invoice reference'
end
```

---

### 6.1.2. Testing de Payment

**Casos críticos:**

```ruby
RSpec.describe Payments::RegisterPayment do
  # 1. Reducción de saldo
  it 'reduces customer balance after payment'
  
  # 2. Validaciones
  it 'requires customer with credit account'
  it 'validates amount is positive'
  it 'validates payment_method'
  
  # 3. Métodos de pago
  it 'accepts all payment methods'
end
```

---

### 6.2. Testing

**Framework:** RSpec (o Minitest)

**Prioridades:**
1. Models con lógica importante
2. Services (casos de uso críticos)
3. Requests de flujos críticos (ventas, pagos, compras)
4. System tests para flujos end-to-end

**Flujos críticos a testear:**
- Crear venta con validación de stock
- Anular venta y reversar stock
- Crear compra y actualizar costos
- Cálculo de saldo de cliente
- Cálculo de stock por movimientos

---

## 7. GUÍA PARA AGENTES DE IA

Cuando un agente (Cursor, Claude, ChatGPT) genere código:

### 7.1. DEBE Respetar

✅ **Arquitectura:**
- Lógica de negocio en models/services
- Controllers delgados
- Vistas HAML en `app/views/web/`
- TailwindCSS para estilos

✅ **Reglas de negocio:**
- Todas las de `FLUJOS.md`
- Stock por movimientos (nunca edición directa)
- Validaciones antes de operaciones
- Transacciones para operaciones complejas

✅ **Diseño:**
- Seguir `UI_DESIGN_SPEC.md`
- Reutilizar componentes UI
- Mantener consistencia visual

### 7.2. NO Debe

❌ Crear carpetas nuevas sin justificación
❌ Introducir gems/librerías sin necesidad
❌ Regenerar archivos que ya están correctos
❌ Poner lógica de negocio en controllers
❌ Poner lógica de negocio en vistas
❌ Editar stock directamente

### 7.3. Priorizar

1. **Claridad del código**
2. **Impacto real en el producto**
3. **Mínima complejidad accidental**
4. **Reutilización de código existente**

### 7.4. Antes de Generar Código

1. Leer este documento completo
2. Consultar `FLUJOS.md` para reglas específicas
3. Consultar `CODE_PATTERNS.md` para ejemplos
4. Consultar `UI_DESIGN_SPEC.md` para diseño
5. Revisar código existente similar

### 7.5. Al Generar Código

1. Seguir la estructura de carpetas
2. Usar los patrones establecidos
3. Incluir validaciones apropiadas
4. Manejar errores correctamente
5. Agregar comentarios solo si es necesario
6. Considerar tests desde el principio

---

## 8. DOCUMENTOS RELACIONADOS

### Documentación del Proyecto

1. **FLUJOS.md**
   - Especificación funcional completa
   - Reglas de negocio detalladas
   - Flujos de usuario
   - Casos de uso

2. **UI_DESIGN_SPEC.md**
   - Diseño de todas las pantallas
   - Sistema de diseño (colores, tipografía)
   - Componentes UI
   - Estados y comportamientos

3. **CODE_PATTERNS.md**
   - Ejemplos de código concretos
   - Patrones de implementación
   - Snippets reutilizables
   - Anti-patrones a evitar

### Archivos de Configuración Importantes

- `config/routes.rb` - Rutas del sistema
- `tailwind.config.js` - Configuración de Tailwind
- `db/schema.rb` - Esquema de base de datos
- `Gemfile` - Dependencias del proyecto

---

## 9. PREGUNTAS FRECUENTES

### ¿Cuándo crear un Service vs poner lógica en el Model?

**Service cuando:**
- Afecta múltiples modelos
- Requiere transacción
- Tiene múltiples pasos
- Coordina operaciones complejas

**Model cuando:**
- Cálculo simple de un atributo
- Validación de datos
- Query scope simple
- Comportamiento propio del modelo

### ¿Cuándo usar Turbo Frame vs Turbo Stream?

**Turbo Frame:**
- Reemplazar una sección específica de la página
- Navegación dentro de un frame
- Formularios que actualizan su contenedor

**Turbo Stream:**
- Múltiples actualizaciones simultáneas
- Agregar/quitar elementos de lista
- Actualizar varias partes de la página

### ¿Cómo manejar errores en Services?

Siempre devolver `Result` con:
- `success?: false`
- `errors: [array de mensajes]`
- `record: nil` (o el registro parcial si aplica)

### ¿Dónde va la lógica de formateo?

- **Modelos:** cálculos de negocio (totales, márgenes)
- **Helpers:** formateo para vistas (fechas, moneda)
- **Vistas:** solo presentación

### ¿Cómo testear Services?

Ver ejemplos en `CODE_PATTERNS.md`, pero en resumen:
- Arrange: preparar datos
- Act: llamar al service
- Assert: verificar `success?`, `record`, `errors`
- Verificar efectos secundarios (stock, saldos)

---

## 10. CHECKLIST PARA NUEVAS FEATURES

Antes de considerar una feature completa:

- [ ] Código sigue la arquitectura (models/services/controllers/views)
- [ ] Respeta todas las reglas de negocio de FLUJOS.md
- [ ] Sigue el diseño de UI_DESIGN_SPEC.md
- [ ] Usa HAML para vistas
- [ ] Usa TailwindCSS para estilos
- [ ] Controllers son delgados
- [ ] Services devuelven Result consistente
- [ ] Stock se maneja por movimientos (si aplica)
- [ ] Validaciones apropiadas
- [ ] Manejo de errores correcto
- [ ] Tests agregados/actualizados
- [ ] Sin warnings de RuboCop (si está configurado)
- [ ] Funciona en ambiente de desarrollo
- [ ] README actualizado (si aplica)

---

**Última actualización:** Noviembre 2025  
**Versión:** 1.0  

Para contribuir o reportar problemas con esta guía, contactar al equipo de desarrollo.