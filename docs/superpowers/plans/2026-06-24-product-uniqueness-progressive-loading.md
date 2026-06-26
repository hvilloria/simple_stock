# Unicidad de productos para carga progresiva — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Relajar la validación de unicidad del modelo `Product` para que solo enforce cuando `origin` está presente, habilitando la carga progresiva (primero origen, marca después).

**Architecture:** Cambio puntual en una validación de ActiveRecord. La regla de identidad sigue siendo `sku (OEM) + product_type + origin + brand`, pero la parte de `uniqueness` pasa a ser condicional a `origin.present?`. El índice DB queda intacto (lenient). Sin migraciones, sin tocar importadores.

**Tech Stack:** Rails 7.2, RSpec, FactoryBot, shoulda-matchers, PostgreSQL.

## Global Constraints

- **Spec de referencia:** `docs/superpowers/specs/2026-06-24-product-uniqueness-progressive-loading-design.md` — leerlo antes de empezar.
- **Stock rule (no aplica aquí pero vigente):** stock nunca se muta directo. Este plan no toca stock.
- **No tocar el índice DB** `index_products_on_variant_uniqueness` — queda lenient (NULLS DISTINCT) a propósito.
- **No tocar importadores** (`SalesLedger::ImportCsv`, `Inventory::SyncFromCsv`) ni hacer `origin` requerido.
- **`product_type` permanece** dentro de la clave de unicidad.
- **Commits/branch:** este proyecto **NO commitea sin permiso explícito del usuario** en el momento. Los pasos de commit están listados como parte del flujo TDD, pero ejecutar `git commit` requiere el OK del usuario. Idealmente trabajar en una rama nueva (ej. `feat_15-product-uniqueness-progressive-loading`), creándola solo con autorización.
- **Lint:** `bundle exec rubocop` debe pasar en los archivos tocados.

---

### Task 1: Relajar la validación de unicidad en `Product` (condicional a `origin`)

**Files:**
- Modify: `app/models/product.rb` (bloque de Validations, ~líneas 49-52)
- Test: `spec/models/product_spec.rb` (bloque `describe 'validations'`, ~líneas 8-13)

**Interfaces:**
- Consumes: factory `:product` (default `origin: nil`, `product_type: nil`, `brand: "Generic Brand"`).
- Produces: comportamiento de `Product#valid?` — uniqueness de `sku` scopeada a `[:product_type, :origin, :brand]` solo cuando `origin.present?`.

- [ ] **Step 1: Escribir los tests de la matriz (fallan los del caso origin nil)**

En `spec/models/product_spec.rb`, dentro de `describe 'validations' do` (después del `it { is_expected.to validate_presence_of(:name) }` de la línea ~13), agregar este bloque nuevo:

```ruby
    describe 'sku uniqueness (condicional a origin)' do
      it 'permite duplicar sku+type cuando origin es nil (no valida)' do
        create(:product, sku: 'OEM-1', product_type: 'oem', origin: nil, brand: nil)
        dup = build(:product, sku: 'OEM-1', product_type: 'oem', origin: nil, brand: nil)

        expect(dup).to be_valid
      end

      it 'bloquea el duplicado exacto cuando hay origin (brand nil)' do
        create(:product, sku: 'OEM-1', product_type: 'oem', origin: 'japan', brand: nil)
        dup = build(:product, sku: 'OEM-1', product_type: 'oem', origin: 'japan', brand: nil)

        expect(dup).not_to be_valid
        expect(dup.errors[:sku]).to be_present
      end

      it 'permite mismo sku+type con distinto origin' do
        create(:product, sku: 'OEM-1', product_type: 'oem', origin: 'japan', brand: nil)
        other = build(:product, sku: 'OEM-1', product_type: 'oem', origin: 'china', brand: nil)

        expect(other).to be_valid
      end

      it 'permite mismo sku+type+origin con distinta marca' do
        create(:product, sku: 'OEM-1', product_type: 'oem', origin: 'japan', brand: nil)
        other = build(:product, sku: 'OEM-1', product_type: 'oem', origin: 'japan', brand: 'Honda')

        expect(other).to be_valid
      end

      it 'bloquea el duplicado exacto con la clave completa (origin + marca)' do
        create(:product, sku: 'OEM-1', product_type: 'oem', origin: 'japan', brand: 'Honda')
        dup = build(:product, sku: 'OEM-1', product_type: 'oem', origin: 'japan', brand: 'Honda')

        expect(dup).not_to be_valid
        expect(dup.errors[:sku]).to be_present
      end
    end
```

- [ ] **Step 2: Correr los tests nuevos y verificar que el caso "origin nil" falla**

Run: `bundle exec rspec spec/models/product_spec.rb -e "uniqueness (condicional a origin)"`
Expected: FALLA el ejemplo `permite duplicar sku+type cuando origin es nil (no valida)` (la validación actual es incondicional y bloquea ese duplicado). Los otros 4 ejemplos pasan (reflejan comportamiento ya existente).

- [ ] **Step 3: Implementar el cambio en el modelo + remover el matcher obsoleto**

En `app/models/product.rb`, reemplazar el bloque actual:

```ruby
  # Validations
  # SKU es el código OEM, puede repetirse entre variantes
  # La unicidad se garantiza por la combinación: sku + product_type + brand + origin
  validates :sku, presence: true, uniqueness: { scope: [ :product_type, :brand, :origin ] }
```

por:

```ruby
  # Validations
  # SKU es el código OEM, puede repetirse entre variantes.
  # La identidad de una variante es: sku + product_type + origin + brand.
  # La unicidad se enforça SOLO cuando hay `origin` presente, para permitir la
  # carga progresiva (primero el origen, la marca se afina después) y que los
  # importadores creen productos con origin/brand en nil sin chocar.
  # El índice DB (index_products_on_variant_uniqueness) queda lenient
  # (NULLS DISTINCT): es backstop para filas completas; el modelo es el enforcer real.
  validates :sku, presence: true
  validates :sku, uniqueness: { scope: [ :product_type, :origin, :brand ] },
                  if: -> { origin.present? }
```

En `spec/models/product_spec.rb`, eliminar la línea del matcher shoulda que asume unicidad incondicional (queda obsoleta porque ahora es condicional a `origin`):

```ruby
    it { is_expected.to validate_uniqueness_of(:sku).scoped_to(:product_type, :brand, :origin) }
```

(El `subject { build(:product) }` tiene `origin: nil`, así que ese matcher fallaría tras el cambio. La cobertura de unicidad ahora vive en el bloque `describe 'sku uniqueness (condicional a origin)'` del Step 1.)

- [ ] **Step 4: Correr el spec completo del modelo y verificar verde**

Run: `bundle exec rspec spec/models/product_spec.rb`
Expected: PASS — todos los ejemplos (incluidos los 5 nuevos) en verde, sin el matcher removido.

- [ ] **Step 5: Verificar que no se rompieron los importadores ni specs relacionados**

Run: `bundle exec rspec spec/services/sales_ledger/import_csv_spec.rb spec/services/inventory/sync_from_csv_spec.rb 2>/dev/null; echo "(si algún archivo no existe, ignorar)"`
Expected: PASS (o "no such file" si no existen). El cambio solo relaja la validación, no debería afectar a los importadores que ya hacen `find_by` antes de crear.

- [ ] **Step 6: Lint**

Run: `bundle exec rubocop app/models/product.rb spec/models/product_spec.rb`
Expected: `no offenses detected`.

- [ ] **Step 7: Commit** (solo con permiso explícito del usuario — ver Global Constraints)

```bash
git add app/models/product.rb spec/models/product_spec.rb
git commit -m "feat: relax product uniqueness to enforce only when origin present

Enables progressive loading (origin first, brand later). Uniqueness scope
stays sku + product_type + origin + brand but only validates when origin is
present; DB index remains lenient (NULLS DISTINCT) as a backstop.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Documentar la regla en `WORKING_CONTEXT.md`

**Files:**
- Modify: `WORKING_CONTEXT.md` (sección `## Core flows`, agregar subsección de Productos; o `## Key constraints`)

**Interfaces:**
- Consumes: nada.
- Produces: documentación de la regla de unicidad y la asimetría modelo/DB.

- [ ] **Step 1: Agregar la subsección de unicidad de productos**

En `WORKING_CONTEXT.md`, dentro de `## Key constraints`, agregar un bullet nuevo (después del bullet de stock, manteniendo el estilo de los existentes):

```markdown
* **Unicidad de productos (variantes):** la identidad de una variante es **`sku (OEM) + product_type + origin + brand`**. La **validación de modelo** (`Product`) enforça la unicidad **solo cuando `origin` está presente** (`if: -> { origin.present? }`), para permitir carga progresiva: se carga primero el origen y la **marca se afina después**; con `origin` en `nil` (importadores / carga cruda) no valida. El **índice DB** `index_products_on_variant_uniqueness` queda **lenient** (Postgres NULLS DISTINCT → no bloquea duplicados con `origin`/`brand` en `nil`): es **backstop para filas completas**, el **modelo es el enforcer real**. `sku` = código OEM (se repite entre variantes); `origin`/`brand` son nullable.
```

- [ ] **Step 2: Verificar que el archivo quedó coherente**

Run: `grep -n "Unicidad de productos" WORKING_CONTEXT.md`
Expected: una línea de match con el bullet agregado.

- [ ] **Step 3: Commit** (solo con permiso explícito del usuario)

```bash
git add WORKING_CONTEXT.md
git commit -m "docs: document product variant uniqueness rule in WORKING_CONTEXT

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**1. Spec coverage:**
- Relajar validación condicional a `origin.present?` → Task 1, Step 3. ✅
- Matriz de tests (origin nil / origin+brand nil / distinto origin / distinta marca / clave completa) → Task 1, Step 1. ✅
- No tocar índice DB → respetado (Global Constraints + ningún step lo toca). ✅
- No tocar importadores / no requerir origin → respetado; verificado en Step 5. ✅
- `product_type` en la clave → conservado en el nuevo scope. ✅
- Doc en WORKING_CONTEXT → Task 2. ✅
- Manejo del matcher shoulda obsoleto (`product_spec.rb:12`) → Task 1, Step 3 (removido). ✅

**2. Placeholder scan:** Sin TBD/TODO; todo el código de tests y modelo está completo. ✅

**3. Type consistency:** El scope `[:product_type, :origin, :brand]` y la condición `origin.present?` son consistentes entre el modelo (Step 3) y la doc (Task 2). Los tests usan los mismos nombres de campos (`product_type`, `origin`, `brand`, `sku`). ✅
