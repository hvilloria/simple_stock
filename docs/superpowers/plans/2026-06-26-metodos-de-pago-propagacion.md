# Propagación de los 5 métodos de pago — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Propagar los 5 métodos de pago oficiales (`cash bank_qr bank_card bank_transfer mercado_pago`) a la UI, las etiquetas legibles, los badges de color y los specs/factories, eliminando los valores viejos (`transfer/check/card`).

**Architecture:** Una sola fuente de verdad en el modelo `Payment` (etiquetas + opciones para selects); `ApplicationHelper` delega al modelo y agrega la paleta de colores de los badges, conservando la clave `bank` del subsistema Sales Ledger (fuera de alcance). Las 4 vistas dejan de hardcodear los métodos.

**Tech Stack:** Rails 7.2, HAML, TailwindCSS, RSpec, FactoryBot.

## Global Constraints

- HAML only (no ERB) en las vistas.
- Fechas/horas timezone-aware: `Date.current` / `Time.current`, nunca `Date.today` / `Time.now`.
- No tocar el subsistema Sales Ledger (`SalesLedger::Entry`, `SalesLedger::ImportCsv`, `lib/tasks/import_sales.rake`): mantiene su set propio `cash bank mercado_pago`.
- No tocar la lógica de la regla "descuento solo efectivo": el ancla `"cash"` en los controllers Stimulus se conserva tal cual.
- Etiquetas oficiales (clave → label): `cash`→Efectivo · `bank_qr`→Banco QR · `bank_card`→Banco Tarjeta · `bank_transfer`→Banco Transferencia · `mercado_pago`→Mercado Pago.
- Paleta de badges (texto blanco): `cash`→`bg-green-900` · todo `bank_*` y `bank`→`bg-blue-900` · `mercado_pago`→`bg-sky-400`.
- Correr `bundle exec rubocop` antes de cada commit y dejarlo limpio.

---

### Task 1: Fuente de verdad en el modelo `Payment`

**Files:**
- Modify: `app/models/payment.rb:9-19`
- Test: `spec/models/payment_spec.rb`

**Interfaces:**
- Produces:
  - `Payment::PAYMENT_METHOD_LABELS` → `Hash{String=>String}` (ordenado, 5 entradas).
  - `Payment::PAYMENT_METHODS` → `Array<String>` (las keys del hash, congelado).
  - `Payment.method_label(key)` → `String` (etiqueta; fallback `key.to_s.humanize`).
  - `Payment.method_options` → `Array<[String, String]>` = `[[label, key], …]` para `options_for_select`.

- [ ] **Step 1: Escribir los tests que fallan**

En `spec/models/payment_spec.rb`, agregar un nuevo bloque `describe "payment method catalog"` antes del `end` final del `RSpec.describe` (dejá el `describe "factory"` existente intacto — Task 4 lo actualiza):

```ruby
  describe "payment method catalog" do
    it "defines exactly the five official methods" do
      expect(Payment::PAYMENT_METHODS).to eq(%w[cash bank_qr bank_card bank_transfer mercado_pago])
    end

    it "keeps 'cash' as the discount anchor key" do
      expect(Payment::PAYMENT_METHODS).to include("cash")
    end

    describe ".method_label" do
      it "returns the human label for a known key" do
        expect(Payment.method_label("bank_card")).to eq("Banco Tarjeta")
        expect(Payment.method_label("mercado_pago")).to eq("Mercado Pago")
      end

      it "humanizes an unknown key as a fallback" do
        expect(Payment.method_label("foo_bar")).to eq("Foo bar")
      end
    end

    describe ".method_options" do
      it "returns [label, key] pairs in catalog order for selects" do
        expect(Payment.method_options).to eq([
          [ "Efectivo", "cash" ],
          [ "Banco QR", "bank_qr" ],
          [ "Banco Tarjeta", "bank_card" ],
          [ "Banco Transferencia", "bank_transfer" ],
          [ "Mercado Pago", "mercado_pago" ]
        ])
      end
    end
  end
```

- [ ] **Step 2: Correr los tests para verificar que fallan**

Run: `bundle exec rspec spec/models/payment_spec.rb -e "payment method catalog"`
Expected: FAIL (`NoMethodError: undefined method 'method_label'` / `method_options`).

- [ ] **Step 3: Implementar la fuente de verdad en el modelo**

En `app/models/payment.rb`, reemplazar el bloque de constantes (líneas 9-19, desde el comentario `# Constants` hasta la definición de `PAYMENT_METHODS`) por:

```ruby
  # Constants
  # Métodos de pago oficiales — fuente única de verdad (etiquetas + opciones de UI).
  # Ver docs/decisiones/2026-06-26-metodos-de-pago.md.
  # `cash` se conserva como clave: la regla "descuento solo efectivo"
  # (Payments::CollectSaleNote / CollectOnAccount) compara contra "cash".
  PAYMENT_METHOD_LABELS = {
    "cash"          => "Efectivo",
    "bank_qr"       => "Banco QR",
    "bank_card"     => "Banco Tarjeta",
    "bank_transfer" => "Banco Transferencia",
    "mercado_pago"  => "Mercado Pago"
  }.freeze

  PAYMENT_METHODS = PAYMENT_METHOD_LABELS.keys.freeze

  def self.method_label(key)
    PAYMENT_METHOD_LABELS.fetch(key.to_s, key.to_s.humanize)
  end

  def self.method_options
    PAYMENT_METHOD_LABELS.map { |key, label| [ label, key ] }
  end
```

- [ ] **Step 4: Correr los tests para verificar que pasan**

Run: `bundle exec rspec spec/models/payment_spec.rb -e "payment method catalog"`
Expected: PASS.

- [ ] **Step 5: Lint + commit**

```bash
bundle exec rubocop app/models/payment.rb
git add app/models/payment.rb spec/models/payment_spec.rb
git commit -m "feat: single source of truth for payment methods on Payment model"
```

---

### Task 2: Etiquetas y badges de color en `ApplicationHelper`

**Files:**
- Modify: `app/helpers/application_helper.rb:13-23`
- Test: `spec/helpers/application_helper_spec.rb` (Create)

**Interfaces:**
- Consumes: `Payment::PAYMENT_METHOD_LABELS` (Task 1).
- Produces (firmas sin cambios):
  - `payment_method_label(method)` → `String` (cubre los 5 métodos + `bank` del ledger).
  - `payment_method_badge_class(method)` → `String` (clases Tailwind, texto blanco; fallback `bg-slate-100 text-slate-700`).

- [ ] **Step 1: Escribir los tests que fallan**

Crear `spec/helpers/application_helper_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationHelper, type: :helper do
  describe "#payment_method_label" do
    it "labels the five Payment methods" do
      expect(helper.payment_method_label("cash")).to eq("Efectivo")
      expect(helper.payment_method_label("bank_qr")).to eq("Banco QR")
      expect(helper.payment_method_label("bank_card")).to eq("Banco Tarjeta")
      expect(helper.payment_method_label("bank_transfer")).to eq("Banco Transferencia")
      expect(helper.payment_method_label("mercado_pago")).to eq("Mercado Pago")
    end

    it "still labels the ledger's 'bank' bucket" do
      expect(helper.payment_method_label("bank")).to eq("Banco")
    end

    it "humanizes unknown keys" do
      expect(helper.payment_method_label("foo")).to eq("Foo")
    end
  end

  describe "#payment_method_badge_class" do
    it "returns dark green for cash" do
      expect(helper.payment_method_badge_class("cash")).to eq("bg-green-900 text-white")
    end

    it "returns dark blue for every bank method and the ledger bucket" do
      %w[bank_qr bank_card bank_transfer bank].each do |method|
        expect(helper.payment_method_badge_class(method)).to eq("bg-blue-900 text-white")
      end
    end

    it "returns light blue for mercado_pago" do
      expect(helper.payment_method_badge_class("mercado_pago")).to eq("bg-sky-400 text-white")
    end

    it "falls back to slate for unknown keys" do
      expect(helper.payment_method_badge_class("foo")).to eq("bg-slate-100 text-slate-700")
    end
  end
end
```

- [ ] **Step 2: Correr los tests para verificar que fallan**

Run: `bundle exec rspec spec/helpers/application_helper_spec.rb`
Expected: FAIL (las etiquetas de `bank_card`/`bank_qr`/etc. caen al fallback `humanize`, los badges no coinciden).

- [ ] **Step 3: Implementar las constantes nuevas**

En `app/helpers/application_helper.rb`, reemplazar las constantes `PAYMENT_METHOD_BADGE_CLASSES` y `PAYMENT_METHOD_LABELS` (líneas 13-23) por:

```ruby
  PAYMENT_METHOD_BADGE_CLASSES = {
    "cash"          => "bg-green-900 text-white",  # verde oscuro
    "bank_qr"       => "bg-blue-900 text-white",   # azul oscuro
    "bank_card"     => "bg-blue-900 text-white",
    "bank_transfer" => "bg-blue-900 text-white",
    "bank"          => "bg-blue-900 text-white",   # ledger (cash/bank/mercado_pago)
    "mercado_pago"  => "bg-sky-400 text-white"     # azul claro
  }.freeze

  # Delega al catálogo del modelo Payment y agrega "bank" para las vistas del
  # Sales Ledger (subsistema con su propio set de métodos).
  PAYMENT_METHOD_LABELS = Payment::PAYMENT_METHOD_LABELS.merge("bank" => "Banco").freeze
```

(Los métodos `payment_method_badge_class` y `payment_method_label` en las líneas 33-39 no cambian.)

- [ ] **Step 4: Correr los tests para verificar que pasan**

Run: `bundle exec rspec spec/helpers/application_helper_spec.rb`
Expected: PASS.

- [ ] **Step 5: Lint + commit**

```bash
bundle exec rubocop app/helpers/application_helper.rb
git add app/helpers/application_helper.rb spec/helpers/application_helper_spec.rb
git commit -m "feat: payment method labels and colored badges for the five methods"
```

---

### Task 3: Vistas — usar la fuente de verdad y el badge de color

**Files:**
- Modify: `app/views/web/customers/payments/new.html.haml:3,122-123`
- Modify: `app/views/web/sale_notes/payments/new.html.haml:64-65`
- Modify: `app/views/web/payments_on_account/payments/new.html.haml:58-59`
- Modify: `app/views/web/customers/show.html.haml:4,146`

**Interfaces:**
- Consumes: `Payment.method_options` (Task 1), `payment_method_label` / `payment_method_badge_class` (Task 2).

Esta tarea no agrega specs nuevos: es un reemplazo de markup verificado por los request specs existentes (Task 5) y un chequeo manual. Cada paso es un edit puntual.

- [ ] **Step 1: Customer payments form — quitar el array hardcodeado**

En `app/views/web/customers/payments/new.html.haml`:
- Borrar la línea 3 completa:
  ```haml
  - payment_method_options = [ [ "Efectivo", "cash" ], [ "Transferencia", "transfer" ], [ "Cheque", "check" ], [ "Tarjeta", "card" ] ]
  ```
- En el `select_tag` (línea 123), reemplazar `options_for_select(payment_method_options, "cash")` por:
  ```haml
                      options_for_select(Payment.method_options, "cash"),
  ```

- [ ] **Step 2: Sale note payments form**

En `app/views/web/sale_notes/payments/new.html.haml`, línea 65, reemplazar:
```haml
                  options_for_select([["Efectivo", "cash"], ["Transferencia", "transfer"], ["Cheque", "check"], ["Tarjeta", "card"]], "cash"),
```
por:
```haml
                  options_for_select(Payment.method_options, "cash"),
```

- [ ] **Step 3: On-account payments form**

En `app/views/web/payments_on_account/payments/new.html.haml`, línea 59, reemplazar:
```haml
              options_for_select([["Efectivo", "cash"], ["Transferencia", "transfer"], ["Cheque", "check"], ["Tarjeta", "card"]], "cash"),
```
por:
```haml
              options_for_select(Payment.method_options, "cash"),
```

- [ ] **Step 4: Customer show — badge de color en vez de texto plano**

En `app/views/web/customers/show.html.haml`:
- Borrar la línea 4 completa:
  ```haml
  - payment_method_labels = { "cash" => "Efectivo", "transfer" => "Transferencia", "check" => "Cheque", "card" => "Tarjeta" }
  ```
- Reemplazar la línea 146:
  ```haml
                      = payment_method_labels[payment.payment_method] || payment.payment_method
  ```
  por un badge de color:
  ```haml
                      %span.inline-flex.items-center.px-2.5.py-1.rounded-full.text-xs.font-medium{ class: payment_method_badge_class(payment.payment_method) }
                        = payment_method_label(payment.payment_method)
  ```

- [ ] **Step 5: Verificar que el server arranca y las vistas renderizan**

Run: `bundle exec rspec spec/requests/web/customers/payments_spec.rb spec/requests/web/sale_notes/payments_spec.rb`
Expected: PASS (los GET de `new` renderizan sin error con las vistas nuevas). Si algún ejemplo usa `"transfer"` en el POST, se arregla en Task 5 — correr esos archivos de nuevo al final.

- [ ] **Step 6: Lint + commit**

```bash
git add app/views/web/customers/payments/new.html.haml \
        app/views/web/sale_notes/payments/new.html.haml \
        app/views/web/payments_on_account/payments/new.html.haml \
        app/views/web/customers/show.html.haml
git commit -m "feat: render payment method selects and badges from the shared catalog"
```

---

### Task 4: Factory y trait specs del modelo

**Files:**
- Modify: `spec/factories/payments.rb:11-24`
- Modify: `spec/models/payment_spec.rb:50-69`

**Interfaces:**
- Consumes: `Payment::PAYMENT_METHODS` (Task 1).
- Produces: traits `:bank_qr`, `:bank_card`, `:bank_transfer`, `:mercado_pago` en la factory `:payment`.

- [ ] **Step 1: Actualizar los trait specs (que fallarán)**

En `spec/models/payment_spec.rb`, reemplazar el bloque `describe "factory"` (líneas 50-69) por:

```ruby
  describe "factory" do
    it "has a valid default factory" do
      expect(create(:payment)).to be_valid
    end

    it "has a :bank_qr trait" do
      expect(create(:payment, :bank_qr).payment_method).to eq("bank_qr")
    end

    it "has a :bank_card trait" do
      expect(create(:payment, :bank_card).payment_method).to eq("bank_card")
    end

    it "has a :bank_transfer trait" do
      expect(create(:payment, :bank_transfer).payment_method).to eq("bank_transfer")
    end

    it "has a :mercado_pago trait" do
      expect(create(:payment, :mercado_pago).payment_method).to eq("mercado_pago")
    end
  end
```

- [ ] **Step 2: Correr los tests para verificar que fallan**

Run: `bundle exec rspec spec/models/payment_spec.rb -e factory`
Expected: FAIL (`KeyError: Trait not registered: "bank_qr"`).

- [ ] **Step 3: Reemplazar los traits viejos en la factory**

En `spec/factories/payments.rb`, reemplazar los traits `:transfer`, `:check`, `:card` (líneas 11-24) por:

```ruby
    trait :bank_qr do
      payment_method { "bank_qr" }
      notes { "Banco QR" }
    end

    trait :bank_card do
      payment_method { "bank_card" }
      notes { "Banco Tarjeta" }
    end

    trait :bank_transfer do
      payment_method { "bank_transfer" }
      notes { "Banco Transferencia" }
    end

    trait :mercado_pago do
      payment_method { "mercado_pago" }
      notes { "Mercado Pago" }
    end
```

- [ ] **Step 4: Correr los tests para verificar que pasan**

Run: `bundle exec rspec spec/models/payment_spec.rb`
Expected: PASS (todo el archivo, incluyendo el catálogo de Task 1).

- [ ] **Step 5: Lint + commit**

```bash
bundle exec rubocop spec/factories/payments.rb spec/models/payment_spec.rb
git add spec/factories/payments.rb spec/models/payment_spec.rb
git commit -m "test: replace transfer/check/card payment factory traits with the new methods"
```

---

### Task 5: Specs de servicios y requests — migrar `"transfer"` a `"bank_transfer"`

**Files:**
- Modify: `spec/services/payments/collect_sale_note_spec.rb:55,126,133`
- Modify: `spec/services/payments/collect_on_account_spec.rb:50`
- Modify: `spec/services/payments/allocate_payment_spec.rb:157,164,166,195`
- Modify: `spec/requests/web/customers/payments_spec.rb:106`
- Modify: `spec/requests/web/sale_notes/payments_spec.rb:47`

**Interfaces:**
- Consumes: `Payment::PAYMENT_METHODS` (Task 1) — `"bank_transfer"` es un método válido.

`"bank_transfer"` es el reemplazo natural de `"transfer"` (es transferencia bancaria). El reemplazo es literal `"transfer"` → `"bank_transfer"` en cada archivo, incluyendo las búsquedas `Payment.find_by(payment_method: …)` y las aserciones `contain_exactly`.

- [ ] **Step 1: Reemplazar el literal en cada archivo**

Reemplazar **todas** las apariciones de `"transfer"` por `"bank_transfer"` en estos archivos (no hay `"check"`/`"card"` como métodos en estos archivos):

- `spec/services/payments/collect_sale_note_spec.rb` — líneas 55, 126 (`payment_method: "transfer"` → `"bank_transfer"`) y 133 (`contain_exactly("cash", "transfer")` → `contain_exactly("cash", "bank_transfer")`).
- `spec/services/payments/collect_on_account_spec.rb` — línea 50.
- `spec/services/payments/allocate_payment_spec.rb` — líneas 157, 195 (`payment_method: "transfer"`), 164 (`Payment.find_by(payment_method: "transfer")` → `"bank_transfer"`) y la variable local `transfer_payment` queda igual de nombre (solo cambia el string del método).
- `spec/requests/web/customers/payments_spec.rb` — línea 106.
- `spec/requests/web/sale_notes/payments_spec.rb` — línea 47.

Comando para hacerlo de una y verificar que no queda ninguno:

```bash
sed -i '' 's/"transfer"/"bank_transfer"/g' \
  spec/services/payments/collect_sale_note_spec.rb \
  spec/services/payments/collect_on_account_spec.rb \
  spec/services/payments/allocate_payment_spec.rb \
  spec/requests/web/customers/payments_spec.rb \
  spec/requests/web/sale_notes/payments_spec.rb
grep -rn '"transfer"\|"check"\|"card"' spec/ || echo "OK: sin métodos viejos"
```

Expected: `OK: sin métodos viejos`.

- [ ] **Step 2: Correr los specs afectados para verificar que pasan**

Run:
```bash
bundle exec rspec spec/services/payments/collect_sale_note_spec.rb \
  spec/services/payments/collect_on_account_spec.rb \
  spec/services/payments/allocate_payment_spec.rb \
  spec/requests/web/customers/payments_spec.rb \
  spec/requests/web/sale_notes/payments_spec.rb
```
Expected: PASS.

- [ ] **Step 3: Lint + commit**

```bash
bundle exec rubocop spec/services/payments/ spec/requests/web/customers/payments_spec.rb spec/requests/web/sale_notes/payments_spec.rb
git add spec/services/payments/ spec/requests/web/customers/payments_spec.rb spec/requests/web/sale_notes/payments_spec.rb
git commit -m "test: migrate service and request specs from transfer to bank_transfer"
```

---

### Task 6: Verificación final

**Files:** ninguno (gate de cierre).

- [ ] **Step 1: Suite completa**

Run: `bundle exec rspec`
Expected: PASS (0 failures).

- [ ] **Step 2: Lint completo**

Run: `bundle exec rubocop`
Expected: sin offenses.

- [ ] **Step 3: No quedan métodos viejos en el código de la app**

Run: `grep -rn '"transfer"\|"check"\|"card"' app/ spec/`
Expected: sin resultados (los únicos `card`/`check` que pueden aparecer son palabras inglesas en comentarios JS como "cards"/"checkbox", no métodos de pago — confirmar caso por caso si grep arroja algo).

- [ ] **Step 4: Chequeo manual en el browser**

Levantar el server (`bin/dev` o `bundle exec rails s`) y verificar:
1. Los 3 formularios de cobro (cuenta de cliente, nota de pago, pago a cuenta) listan los 5 métodos con etiquetas legibles.
2. En `web/customers/:id` (show), los pagos muestran el badge de color correcto (Efectivo verde oscuro, Banco* azul oscuro, Mercado Pago azul claro).
3. El descuento solo se habilita con Efectivo en los 3 formularios.
```
