# Product Edit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Activar la edición de productos vía UI web (precio, marca, origen, tipo, etc.) reusando el `_form` compartido, permitiendo a `admin` y `vendedor`.

**Architecture:** Las rutas (`edit`/`update`) y la `ProductPolicy` ya existen. Se agrega: la acción `edit`/`update` en `Web::ProductsController`, la vista `edit.html.haml` (espejo de `new`), se adapta el `_form` para postear a la URL correcta según persistencia (con `sku` readonly y nota de precio), y se gatea el botón "Editar Producto" por policy. Se amplía la policy a `vendedor`.

**Tech Stack:** Rails 7.2, HAML, TailwindCSS, Pundit, Devise, RSpec (request + policy specs).

## Global Constraints

- **Stock nunca se muta directo:** `current_stock` NO es editable ni está en el form (va por `StockMovement` + `recalculate_current_stock!`). Copiado verbatim de la regla del proyecto.
- **`sku` no editable:** ancla de identidad OEM. Readonly en el form y excluido de los params de update.
- **Write-back se mantiene:** el precio sigue siendo fluido; la edición fija el "próximo default". No se toca `Sales::CreateOrder`.
- **Commit convention del proyecto:** un único commit por feature. NO commitear entre tasks. Mensaje: `type(type_NN): title`. El commit final va en la última task.
- **UI:** respetar `docs/UI_DESIGN_SPEC.md` — reusar el `_form` existente, helper text quieto (`text-xs text-slate-500`), sin emojis/gradientes/botones nuevos, base `slate`.
- **Permisos:** `edit`/`update` = `admin` + `vendedor`. `caja` queda afuera. `create`/`destroy` siguen solo `admin`.
- **Timezone-aware:** usar `Date.current`/`Time.current`, nunca `Date.today`/`Time.now` (no aplica directamente acá pero es regla del proyecto).

---

### Task 1: Policy — permitir a `vendedor` editar productos

**Files:**
- Modify: `app/policies/product_policy.rb` (método `update?`)
- Test: `spec/policies/product_policy_spec.rb`

**Interfaces:**
- Produces: `ProductPolicy#update?` y `#edit?` devuelven `true` para `admin` y `vendedor`, `false` para `caja`. `#edit?` ya delega en `#update?` (sin cambio).

- [ ] **Step 1: Actualizar el test del vendedor y agregar contexto caja**

En `spec/policies/product_policy_spec.rb`, dentro de `context 'for a vendedor'`, **reemplazar** el example existente:

```ruby
    it 'forbids update' do
      expect(subject.update?).to be false
    end
```

por:

```ruby
    it 'permits update' do
      expect(subject.update?).to be true
    end

    it 'permits edit' do
      expect(subject.edit?).to be true
    end
```

Y **agregar** un nuevo contexto al final del `describe` (después de `context 'for an admin'`, antes del `end` de la línea final):

```ruby
  context 'for a caja' do
    let(:user) { build(:user, role: "caja") }

    it 'forbids update' do
      expect(subject.update?).to be false
    end

    it 'forbids edit' do
      expect(subject.edit?).to be false
    end

    it 'forbids create' do
      expect(subject.create?).to be false
    end
  end
```

- [ ] **Step 2: Correr el spec y verificar que falla**

Run: `bundle exec rspec spec/policies/product_policy_spec.rb`
Expected: FAIL — el vendedor todavía tiene `update? == false` (la policy es admin-only), así que `permits update`/`permits edit` fallan.

- [ ] **Step 3: Ampliar la policy**

En `app/policies/product_policy.rb`, reemplazar:

```ruby
  def update?
    user.admin?  # Solo admin edita productos
  end
```

por:

```ruby
  def update?
    user.admin? || user.vendedor?  # Admin y vendedor editan productos; caja no
  end
```

(No tocar `create?`, `destroy?`, `adjust_stock?` — siguen solo admin. `edit?` ya delega en `update?`.)

- [ ] **Step 4: Correr el spec y verificar que pasa**

Run: `bundle exec rspec spec/policies/product_policy_spec.rb`
Expected: PASS (todos los examples, incluido el nuevo contexto `caja`).

---

### Task 2: Controller + vista + form — activar `edit`/`update`

Esta task entrega el flujo de edición end-to-end: acciones `edit`/`update`, la vista `edit`, y el `_form` adaptado (URL por persistencia, `sku` readonly, nota de precio). Se testea con request specs.

**Files:**
- Modify: `app/controllers/web/products_controller.rb` (agregar `edit`, `update`, `update_product_params`)
- Create: `app/views/web/products/edit.html.haml`
- Modify: `app/views/web/products/_form.html.haml` (URL, `sku` readonly, nota de precio)
- Create: `spec/requests/web/products_spec.rb`

**Interfaces:**
- Consumes: `ProductPolicy#update?` (Task 1) vía `authorize @product`. `CurrencyParser#parse_amount` (ya incluido en el controller).
- Produces:
  - `Web::ProductsController#edit` — `GET /web/products/:id/edit`, asigna `@product`, `authorize @product`, renderiza `edit`.
  - `Web::ProductsController#update` — `PATCH /web/products/:id`, `authorize @product`, `@product.update(update_product_params)`; éxito → redirect a `web_product_path(@product)` con `notice`; fallo → `render :edit, status: :unprocessable_entity`.
  - `update_product_params` — permite `name, brand, category, product_type, origin, price_unit, cost_unit, cost_currency, active` (NO `sku`), parseando `price_unit`/`cost_unit` con `parse_amount`.

- [ ] **Step 1: Escribir el request spec (failing)**

Crear `spec/requests/web/products_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Web::Products edit/update", type: :request do
  let(:vendedor) { create(:user, role: "vendedor") }
  let(:admin)    { create(:user, role: "admin") }
  let(:caja)     { create(:user, role: "caja") }
  let(:product)  { create(:product, name: "Disco viejo", brand: "Generic Brand", price_unit: 100) }

  describe "GET /web/products/:id/edit" do
    it "permite a un vendedor abrir la edición" do
      sign_in vendedor
      get edit_web_product_path(product)
      expect(response).to have_http_status(:ok)
    end

    it "permite a un admin abrir la edición" do
      sign_in admin
      get edit_web_product_path(product)
      expect(response).to have_http_status(:ok)
    end

    it "redirige a caja (no autorizado)" do
      sign_in caja
      get edit_web_product_path(product)
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "PATCH /web/products/:id" do
    before { sign_in vendedor }

    it "actualiza campos descriptivos y de precio" do
      patch web_product_path(product), params: {
        product: { name: "Disco nuevo", brand: "TRW", origin: "japan", price_unit: "250,50" }
      }

      expect(response).to redirect_to(web_product_path(product))
      follow_redirect!
      product.reload
      expect(product.name).to eq("Disco nuevo")
      expect(product.brand).to eq("TRW")
      expect(product.origin).to eq("japan")
      expect(product.price_unit).to eq(250.50)
    end

    it "no modifica el sku aunque venga en params" do
      original_sku = product.sku
      patch web_product_path(product), params: {
        product: { sku: "HACKED999", name: "Otro nombre" }
      }

      product.reload
      expect(product.sku).to eq(original_sku)
      expect(product.name).to eq("Otro nombre")
    end

    it "re-renderiza edit con 422 cuando es inválido" do
      patch web_product_path(product), params: {
        product: { name: "" }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(product.reload.name).to eq("Disco viejo")
    end

    it "rechaza un cambio de variante que colisiona con otra variante del mismo sku" do
      existing = create(:product, sku: "OEM-123", product_type: "aftermarket", origin: "china", brand: "Marca1")
      target   = create(:product, sku: "OEM-123", product_type: "aftermarket", origin: "japan",  brand: "Marca1")

      patch web_product_path(target), params: {
        product: { origin: "china" }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(target.reload.origin).to eq("japan")
    end
  end
end
```

- [ ] **Step 2: Correr el spec y verificar que falla**

Run: `bundle exec rspec spec/requests/web/products_spec.rb`
Expected: FAIL — no existe la acción `edit`/`update` (error de acción faltante / template missing / routing al render).

- [ ] **Step 3: Agregar `edit`, `update` y `update_product_params` al controller**

En `app/controllers/web/products_controller.rb`, agregar las acciones `edit` y `update` justo después de `create` (antes de `def search`):

```ruby
    def edit
      @product = Product.find(params[:id])
      authorize @product
    end

    def update
      @product = Product.find(params[:id])
      authorize @product

      if @product.update(update_product_params)
        redirect_to web_product_path(@product), notice: "Producto actualizado exitosamente"
      else
        render :edit, status: :unprocessable_entity
      end
    end
```

Y en la sección `private`, agregar después de `sanitized_product_params`:

```ruby
    def update_product_params
      params_hash = params.require(:product).permit(
        :name, :brand, :category, :product_type, :origin,
        :price_unit, :cost_unit, :cost_currency, :active
      ).to_h

      params_hash[:price_unit] = parse_amount(params_hash[:price_unit]) if params_hash[:price_unit].present?
      params_hash[:cost_unit]  = parse_amount(params_hash[:cost_unit]) if params_hash[:cost_unit].present?

      params_hash
    end
```

(`update_product_params` omite `:sku` a propósito — el sku no se edita.)

- [ ] **Step 4: Crear la vista `edit.html.haml`**

Crear `app/views/web/products/edit.html.haml`:

```haml
- content_for :page_title, "Editar Producto"

.max-w-7xl.mx-auto
  = render "form", product: @product
```

- [ ] **Step 5: Adaptar el `_form` — URL por persistencia, `sku` readonly, nota de precio**

En `app/views/web/products/_form.html.haml`:

**(a)** Reemplazar la primera línea:

```haml
= form_with model: product, url: web_products_path, local: true, data: { controller: "product-form", action: "turbo:submit-start->product-form#handleSubmit" } do |f|
```

por:

```haml
= form_with model: product, url: (product.persisted? ? web_product_path(product) : web_products_path), local: true, data: { controller: "product-form", action: "turbo:submit-start->product-form#handleSubmit" } do |f|
```

**(b)** Reemplazar el campo `sku`:

```haml
            = f.text_field :sku, 
                          class: "w-full px-4 py-3 border border-slate-300 rounded-lg focus:ring-2 focus:ring-slate-500 focus:border-transparent transition-all #{product.errors[:sku].any? ? 'border-red-300' : ''}",
                          placeholder: "Ej: HDC001",
                          autofocus: true,
                          required: true
```

por:

```haml
            = f.text_field :sku, 
                          class: "w-full px-4 py-3 border border-slate-300 rounded-lg focus:ring-2 focus:ring-slate-500 focus:border-transparent transition-all #{product.errors[:sku].any? ? 'border-red-300' : ''} #{'bg-slate-100 text-slate-500 cursor-not-allowed' if product.persisted?}",
                          placeholder: "Ej: HDC001",
                          autofocus: !product.persisted?,
                          required: true,
                          readonly: product.persisted?
            - if product.persisted?
              %p.text-xs.text-slate-500.mt-1 El SKU (código OEM) no se edita.
```

**(c)** Agregar la nota del precio. Ubicar el campo `price_unit` y, justo después del `= f.text_field :price_unit, ...` (antes del cierre de ese `%div`), agregar:

```haml
            - if product.persisted?
              %p.text-xs.text-slate-500.mt-1 Es el precio de partida del próximo pedido. Una venta posterior puede sobrescribirlo automáticamente.
```

- [ ] **Step 6: Correr el spec y verificar que pasa**

Run: `bundle exec rspec spec/requests/web/products_spec.rb`
Expected: PASS (todos los examples).

- [ ] **Step 7: Verificar que no rompimos el flujo de creación**

Run: `bundle exec rspec spec/policies/product_policy_spec.rb spec/requests/web/products_spec.rb spec/models/product_spec.rb`
Expected: PASS. (El `_form` sigue creando productos: con `product` no persistido la URL es `web_products_path` y el `sku` es editable.)

---

### Task 3: Gatear el botón "Editar", documentar y commit

**Files:**
- Modify: `app/views/web/products/show.html.haml:13-14` (gatear botón por policy)
- Modify: `WORKING_CONTEXT.md` (sección Products + nota de limitaciones)
- Test: suite completa + rubocop

- [ ] **Step 1: Gatear el botón "Editar Producto" por policy**

En `app/views/web/products/show.html.haml`, reemplazar:

```haml
      = link_to edit_web_product_path(@product), class: "btn-primary" do
        %span Editar Producto
```

por:

```haml
      - if policy(@product).edit?
        = link_to edit_web_product_path(@product), class: "btn-primary" do
          %span Editar Producto
```

(Así el botón solo aparece para `admin`/`vendedor`; `caja` no lo ve.)

- [ ] **Step 2: Actualizar `WORKING_CONTEXT.md`**

En `WORKING_CONTEXT.md`, en la línea de **Products** (sección "Web surface"), reemplazar la frase que dice que edit/update no están implementados:

```
**`edit`/`update` están ruteados (`config/routes.rb`) pero NO implementados** — no hay acción en el controller, no existe `edit.html.haml`, y `_form` postea siempre a `create`. En la práctica **un producto no se edita después de creado** vía UI, lo cual es **coherente con la decisión de precio local/importado** (ver "Precio local vs importado" abajo).
```

por:

```
**`edit`/`update` implementados** (`admin` + `vendedor` vía `ProductPolicy`; `caja` no). El `_form` postea a `create` o `update` según `product.persisted?`. Editable todo lo que el form renderiza **menos `sku`** (readonly, ancla de identidad OEM) y **`current_stock`** (va por movimientos). Cambiar `origin`/`product_type`/`brand` puede chocar con la unicidad de variante (validación del modelo) → error en el form. El precio editado es el "próximo default": el **write-back** de cada venta lo puede pisar (ver "Precio manual + write-back").
```

Y en la sección **"Precio local vs importado"**, en el punto 2 que dice "El precio NO se edita después de la venta fuera de una nueva venta — no hay edición de producto operativa", reemplazar por:

```
  2. **El precio se puede editar** desde la pantalla de producto (`web/products/:id/edit`, admin+vendedor), pero esa edición fija el "próximo default" — el **write-back** de la siguiente venta lo puede pisar. `current_stock` sigue sin editarse (movimientos); `cost_unit` es editable pero `recalculate_average_cost!` lo recalcula al confirmar compras.
```

- [ ] **Step 3: Correr la suite completa**

Run: `bundle exec rspec`
Expected: all green.

- [ ] **Step 4: Lint**

Run: `bundle exec rubocop`
Expected: no offenses (correr `bundle exec rubocop -a` si hace falta autofix).

- [ ] **Step 5: Commit único del feature**

> Pedir confirmación explícita al usuario antes de commitear (regla del proyecto: no commits sin permiso explícito).

```bash
git add app/policies/product_policy.rb \
        app/controllers/web/products_controller.rb \
        app/views/web/products/edit.html.haml \
        app/views/web/products/_form.html.haml \
        app/views/web/products/show.html.haml \
        spec/policies/product_policy_spec.rb \
        spec/requests/web/products_spec.rb \
        WORKING_CONTEXT.md \
        docs/superpowers/specs/2026-06-26-product-edit-design.md \
        docs/superpowers/plans/2026-06-26-product-edit.md
git commit -m "feat(feat_18): edición de producto (admin + vendedor)"
```

---

## Notas de ejecución

- El número de feature en el commit (`feat_18`) es tentativo — confirmar el siguiente disponible mirando los commits recientes antes de commitear.
- Si al adaptar el `_form` (Task 2, Step 5c) el campo `price_unit` no es trivial de ubicar, buscar `= f.label :price_unit` dentro del Card "Precio y Costo" y agregar la nota dentro de ese mismo `%div`.
