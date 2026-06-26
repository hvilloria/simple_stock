# Unicidad de productos para carga progresiva

- **Fecha:** 2026-06-24
- **Estado:** Aprobado (diseño), pendiente de plan de implementación
- **Archivos afectados:** `app/models/product.rb`, `spec/models/product_spec.rb`, `WORKING_CONTEXT.md`

## Contexto

Ventas definió las reglas de identidad de productos:

1. **Prioridad:** puede haber productos con el **mismo código OEM** pero **distinto origen** — son productos distintos.
2. La **marca** se usará más adelante; hoy no es crítica.
3. Los originales **no** son por defecto de Japón. Hay que poder guardar un repuesto original **con su origen**. La regla: un producto no puede duplicarse scopeado a **OEM → Origen → Marca**.

Durante el análisis se confirmó con el usuario que `product_type` (`oem`/`aftermarket`) **también** forma parte de la clave de identidad: no puede haber dos productos con mismo código, mismo origen, misma marca **y** mismo tipo.

## Estado actual de la app (investigación)

La unicidad de variantes **ya existe**, con 4 dimensiones, en dos niveles:

- **Validación de modelo** (`product.rb`):
  `validates :sku, uniqueness: { scope: [:product_type, :brand, :origin] }`
- **Índice único de DB** (`schema.rb`):
  `index_products_on_variant_uniqueness` sobre `[sku, product_type, brand, origin]`
  (creado en `db/migrate/20251220002519_remove_unique_index_from_products_sku.rb`)

`sku` representa el **código OEM** (puede repetirse entre variantes). `origin` y `brand` son **opcionales** (nullable). Los importadores (`SalesLedger::ImportCsv`, `Inventory::SyncFromCsv`) crean productos con `origin`/`brand` en `nil` a propósito y buscan por `sku + product_type`.

### Hallazgo central: dos niveles con severidad distinta ante `NULL`

| Nivel | Trato de `origin`/`brand` en `nil` | Efecto |
|---|---|---|
| Índice DB | **Lenient** — Postgres NULLS DISTINCT (`NULL ≠ NULL`) | Permite duplicados cuando origin/brand están vacíos |
| Validación de modelo | **Estricta** — Rails genera `... IS NULL` y trata `nil` como valor | Bloquea un 2º producto con mismo OEM+type aunque ambos tengan origin/brand vacíos |

Como **todos los productos importados** tienen `origin`/`brand` en `nil`, el índice DB en la práctica no protege a la mayoría de los productos reales; el que enforça es el modelo.

### Conclusión del análisis

La **regla que pide ventas ya está implementada** (incluso más estricta, con `product_type`). El cambio real no es la regla, sino **relajar la validación de modelo** para permitir la **carga progresiva**: poder ir cargando variantes del mismo OEM mientras los datos aún están incompletos.

El flujo real de carga del usuario: **primero se carga el origen**, la **marca se afina después**. Por eso la condición de relajación se gatea por la presencia de **`origin`**, no de la marca.

## Decisión de diseño

Relajar la validación de unicidad del modelo para que **solo aplique cuando `origin` está presente**. Mantener todo lo demás como está.

### Cambio en `app/models/product.rb`

```ruby
# antes
validates :sku, presence: true, uniqueness: { scope: [:product_type, :brand, :origin] }

# después
validates :sku, presence: true
validates :sku, uniqueness: { scope: [:product_type, :origin, :brand] },
                if: -> { origin.present? }
```

`presence` de `sku` queda siempre activa; solo la parte de `uniqueness` pasa a ser condicional.

### Comportamiento resultante

| Caso | origin | brand | Validación | Resultado |
|---|---|---|---|---|
| Importadores / carga cruda | `nil` | `nil` | No corre | Permite duplicados (carga inicial) |
| Carga normal | `japan` | `nil` | Corre, scope `[type, origin, brand]` | Bloquea otro `12345/oem/japan/(nil)`; permite `12345/oem/china/(nil)` |
| Ya afinado | `japan` | `Honda` | Corre, clave completa | Bloquea exacto; permite distinta marca |

Aclaración conceptual clave (motivo de una duda durante el diseño): la validación de unicidad **no falla porque un campo sea `nil`**; falla solo cuando encuentra **otro** registro con la misma combinación. Con `brand` en `nil`, "sin marca" se compara contra otros registros que **también** tengan `brand` en `nil`. Por eso cargar `12345/oem/japan/(sin marca)` una sola vez guarda sin problema.

## Fuera de alcance (decisiones conscientes)

- **No se toca el índice DB** `index_products_on_variant_uniqueness`: queda lenient (NULLS DISTINCT). Se acepta una **asimetría intencional**: el modelo es el que enforça cuando hay origen; el índice DB es solo backstop para filas completamente especificadas. Se documenta en `WORKING_CONTEXT.md`.
- **No se hace `origin` requerido** — sigue nullable (la carga cruda/importadores lo dejan vacío).
- **No se tocan los importadores** (`SalesLedger::ImportCsv`, `Inventory::SyncFromCsv`): siguen buscando por `sku + product_type` y creando con origin/brand nil.
- **No se limpian duplicados existentes** ni se migra data.
- `product_type` permanece dentro de la clave de unicidad.

## Tests (`spec/models/product_spec.rb`)

Cubrir la matriz acordada:

1. **origin `nil`** → permite crear dos productos con mismo `sku`+`product_type` y origin/brand vacíos (la validación de unicidad no corre).
2. **origin presente + brand `nil`** → bloquea un duplicado exacto (`mismo sku/type/origin`); permite el mismo `sku`+`type` con **distinto** origin.
3. **origin presente + brand presente** → enforça la clave completa; permite el mismo `sku`/`type`/`origin` con **distinta** marca.
4. **presence de `sku`** sigue intacta (un producto sin `sku` es inválido, con o sin origin).

## Documentación

Actualizar `WORKING_CONTEXT.md` agregando la regla de unicidad de productos (hoy no documentada):

- Clave de identidad: `sku (OEM) + product_type + origin + brand`.
- La validación de modelo es **condicional a `origin.present?`** (permite carga progresiva con nulls).
- Asimetría intencional modelo (enforça con origen) vs índice DB (lenient, NULLS DISTINCT, backstop para filas completas).

## Riesgos / notas

- Mientras `brand` esté vacía, dos variantes reales del mismo `OEM+origin` que difieran **solo** en marca no podrán coexistir hasta que se cargue la marca del segundo. Es el comportamiento deseado: la marca es lo que las distingue.
- La asimetría modelo/DB implica que la integridad de unicidad para filas con `origin` presente pero `brand` nula depende **solo** del modelo (no del índice DB, porque `brand` nula es NULLS DISTINCT). Aceptado para esta etapa de carga.
