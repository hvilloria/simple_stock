# Propagación de los 5 métodos de pago a toda la app — Design

**Fecha:** 2026-06-26
**Decisión base:** `docs/decisiones/2026-06-26-metodos-de-pago.md`

## Contexto

El modelo `Payment` ya tiene los 5 métodos oficiales en `PAYMENT_METHODS`
(`cash bank_qr bank_card bank_transfer mercado_pago`), aplicados en la opción B
(mínimo para destrabar el import histórico). Los servicios de cobro
(`Payments::CollectSaleNote`, `CollectOnAccount`, `AllocatePayment`) ya validan
contra esa constante. Falta propagar el cambio a la UI, las etiquetas legibles y
los specs/factories, que todavía referencian los valores viejos
(`transfer/check/card`).

Etiquetas oficiales (clave → label):

| clave | etiqueta |
|---|---|
| `cash` | Efectivo |
| `bank_qr` | Banco QR |
| `bank_card` | Banco Tarjeta |
| `bank_transfer` | Banco Transferencia |
| `mercado_pago` | Mercado Pago |

`cash` se conserva como clave para que la regla "descuento solo efectivo" siga
comparando contra `"cash"` sin cambios.

## Decisiones de diseño

1. **Fuente única de verdad en el modelo `Payment`.** Etiquetas y lista de
   opciones de los selects viven en `Payment`. El `ApplicationHelper` delega al
   modelo. Se eliminan los arrays/hashes hardcodeados de las vistas.
2. **El Sales Ledger queda fuera de alcance.** `SalesLedger::Entry` y
   `SalesLedger::ImportCsv` mantienen su set propio (`cash bank mercado_pago`),
   que es autoconsistente para el import histórico CSV y no está roto. El único
   cuidado: el helper de etiquetas compartido sigue renderizando `bank` → "Banco"
   para las 3 vistas del ledger.

## Cambios

### 1. `app/models/payment.rb` — fuente de verdad

- Agregar `PAYMENT_METHOD_LABELS` (hash ordenado, 5 entradas).
- Derivar la lista existente de las keys: `PAYMENT_METHODS = PAYMENT_METHOD_LABELS.keys.freeze`
  (una sola lista; no pueden driftar).
- `self.method_label(key)` → etiqueta, con fallback `key.to_s.humanize`.
- `self.method_options` → `[[label, key], …]` para `options_for_select`.

```ruby
PAYMENT_METHOD_LABELS = {
  "cash"          => "Efectivo",
  "bank_qr"       => "Banco QR",
  "bank_card"     => "Banco Tarjeta",
  "bank_transfer" => "Banco Transferencia",
  "mercado_pago"  => "Mercado Pago"
}.freeze

PAYMENT_METHODS = PAYMENT_METHOD_LABELS.keys.freeze

def self.method_label(key)  = PAYMENT_METHOD_LABELS.fetch(key.to_s, key.to_s.humanize)
def self.method_options     = PAYMENT_METHOD_LABELS.map { |k, v| [v, k] }
```

### 2. `app/helpers/application_helper.rb` — delega + conserva `bank`

- `PAYMENT_METHOD_LABELS = Payment::PAYMENT_METHOD_LABELS.merge("bank" => "Banco")`
  — así `payment_method_label` sigue sirviendo a las vistas del ledger.
- Reemplazar `PAYMENT_METHOD_BADGE_CLASSES` por la paleta nueva (texto blanco en
  todos), **conservando** la entrada `bank` para el ledger. El fallback actual
  (`bg-slate-100 text-slate-700`) se mantiene para claves desconocidas.
- `payment_method_label` y `payment_method_badge_class` no cambian su firma.

Paleta:

```ruby
PAYMENT_METHOD_BADGE_CLASSES = {
  "cash"          => "bg-green-900 text-white",  # verde oscuro
  "bank_qr"       => "bg-blue-900 text-white",   # azul oscuro
  "bank_card"     => "bg-blue-900 text-white",
  "bank_transfer" => "bg-blue-900 text-white",
  "bank"          => "bg-blue-900 text-white",   # ledger
  "mercado_pago"  => "bg-sky-400 text-white"     # azul claro
}.freeze
```

### 3. Vistas HAML — sacar arrays/hash hardcodeados

- `app/views/web/customers/payments/new.html.haml` (líneas 3 y 123) →
  `options_for_select(Payment.method_options, "cash")`.
- `app/views/web/sale_notes/payments/new.html.haml` (línea 65) → idem.
- `app/views/web/payments_on_account/payments/new.html.haml` (línea 59) → idem.
- `app/views/web/customers/show.html.haml` (líneas 4 y 146) → eliminar el hash
  inline y renderizar el método como **badge de color** (no texto plano):
  un `span` con `payment_method_badge_class(payment.payment_method)` +
  `payment_method_label(payment.payment_method)`. Así el color de la decisión del
  usuario (verde oscuro / azul oscuro / azul claro) aparece en la UI.

### 4. Stimulus — sin cambio funcional

- `sale_note_payment_controller.js` y `on_account_payment_controller.js`
  conservan el ancla `"cash"` de la regla "descuento solo efectivo". Los selects
  ya listan los 5 métodos porque las opciones vienen de la nueva fuente. No se
  edita JS.

### 5. Specs + factories

- `spec/factories/payments.rb`: reemplazar los traits `:transfer/:check/:card`
  por `:bank_qr/:bank_card/:bank_transfer/:mercado_pago` (`cash` sigue default).
- `spec/models/payment_spec.rb`: actualizar los 3 tests de traits; agregar specs
  de `Payment.method_label` y `Payment.method_options`; cubrir que los 5 métodos
  son válidos.
- Service specs (`collect_sale_note_spec`, `collect_on_account_spec`,
  `allocate_payment_spec`) y `spec/requests/web/customers/payments_spec.rb` que
  hardcodean `"transfer"` → `"bank_transfer"`.

## Fuera de alcance

- `SalesLedger::Entry` / `SalesLedger::ImportCsv` (set propio, sin cambios).
- `lib/tasks/import_sales.rake` (ya mapea `bank → bank_card`).
- La lógica de la regla cash-only (sin tocar; solo se verifica que los selects
  listen los métodos nuevos).

## Verificación

- `bundle exec rspec` (suite completa).
- `bundle exec rubocop`.
- Chequeo manual de los 3 formularios de cobro: el select ofrece los 5 métodos
  con sus etiquetas legibles; el descuento solo se habilita con Efectivo.
