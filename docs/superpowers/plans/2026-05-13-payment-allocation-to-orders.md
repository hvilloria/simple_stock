# Payment Allocation to Orders — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Permitir que un pago se distribuya entre múltiples órdenes vía una nueva tabla `payment_allocations`, manteniendo invariante "un `Payment` = un tender (método único)" y reemplazando el flujo actual de pago suelto por un formulario multi-orden.

**Architecture:** Se crea la tabla `payment_allocations(payment_id, order_id, amount)` y se dropea `payments.order_id`. `Order#outstanding_balance` pasa a leer de allocations. Un nuevo servicio `Payments::AllocatePayment` recibe filas con `{order_id, amount, payment_method}`, las agrupa por método, y crea N `Payment`s (uno por método) + sus `PaymentAllocation`s en una sola transacción. El form de cobro pasa de "monto suelto" a "tabla de órdenes pendientes con monto y método por fila + resumen en vivo".

**Tech Stack:** Rails 7.2, PostgreSQL, HAML, TailwindCSS, Stimulus (Hotwire), RSpec, FactoryBot, Pundit.

> **Nota sobre commits:** Este proyecto usa 1 commit por feature completo. NO hay pasos de commit individuales en este plan. El desarrollador hace `git add -A && git commit` una sola vez al final, en el Task 18, después de verificar que todo funciona.

**Spec:** [docs/superpowers/specs/2026-05-12-payment-allocation-to-orders-design.md](../specs/2026-05-12-payment-allocation-to-orders-design.md)

---

## File map

**Crear:**
- `db/migrate/YYYYMMDDHHMMSS_create_payment_allocations.rb`
- `app/models/payment_allocation.rb`
- `app/services/payments/allocate_payment.rb`
- `app/javascript/controllers/payment_allocation_controller.js`
- `spec/factories/payment_allocations.rb`
- `spec/models/payment_allocation_spec.rb`
- `spec/services/payments/allocate_payment_spec.rb`
- `spec/requests/web/customers/payments_spec.rb`

**Modificar:**
- `app/models/payment.rb` — quitar `belongs_to :order`, quitar validación `amount_within_order_total`, agregar `has_many :allocations`
- `app/models/order.rb` — quitar duplicado `has_many :payments`, agregar `has_many :payment_allocations`, refactor `outstanding_balance`
- `app/services/sales/create_order.rb` — `create_initial_payment` ahora crea Payment + Allocation
- `app/services/sales/cancel_order.rb` — destruir solo allocations, no payments
- `app/controllers/web/customers/payments_controller.rb` — usar `Payments::AllocatePayment` con array de allocations
- `app/views/web/customers/payments/new.html.haml` — reescribir con la tabla multi-orden
- `app/views/web/orders/show.html.haml` — leer pagos vía `@order.payment_allocations` (línea ~286)
- `app/views/web/customers/show.html.haml` — leer `order.payment_allocations.sum(:amount)` para columna Cobrado (línea ~105)
- `spec/models/payment_spec.rb` — quitar tests de `belongs_to :order` y `amount_within_order_total`
- `spec/models/order_spec.rb` — actualizar tests de `outstanding_balance` para usar allocations
- `spec/services/sales/create_order_spec.rb` — actualizar tests de `initial_payment`
- `spec/services/sales/cancel_order_spec.rb` — actualizar tests de payments asociados
- `WORKING_CONTEXT.md` — reflejar PaymentAllocation y nuevo flujo
- `docs/DEVELOPMENT_GUIDE.md` — actualizar sección Payments (línea 137-141)

---

## Conventions used in every task

- TDD: escribir test → ver fallar → implementar → ver pasar.
- `bundle exec rspec <path>` para correr tests.
- `bundle exec rubocop <files>` para lint. Si falla, `bundle exec rubocop -a <files>`.
- Los tests de modelo usan `build` / `create` con FactoryBot; los request specs usan `sign_in`.
- Estilo de mensajes de flash y validaciones: español neutro.
- **No hay commits intermedios.** Al final de cada task, dejar el árbol con cambios sin commitear.

---

## Task 1: Setup — branch nueva desde main + baseline verde

**Files:** ninguno (solo git).

- [ ] **Step 1: Verificar que la rama actual está limpia**

```bash
git status
```

Expected: `nothing to commit, working tree clean`. Si hay cambios sin commitear, detener y resolverlos primero.

- [ ] **Step 2: Crear branch nueva desde `origin/main`**

```bash
git fetch origin
git checkout -b feat_06-payment-allocation origin/main
```

Expected: `Switched to a new branch 'feat_06-payment-allocation'`.

- [ ] **Step 3: Verificar baseline de tests**

```bash
bundle exec rspec
```

Expected: suite completa verde. Anotar el número de ejemplos. Si hay fallos preexistentes, anotar y NO continuar sin consultar al usuario.

- [ ] **Step 4: Verificar lint baseline**

```bash
bundle exec rubocop
```

Expected: `no offenses detected` (o el estado que tenga `main`).

---

## Task 2: Migración — crear `payment_allocations` y dropear `payments.order_id`

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_create_payment_allocations.rb`

- [ ] **Step 1: Generar la migración**

```bash
bin/rails generate migration CreatePaymentAllocations
```

Expected: archivo creado en `db/migrate/YYYYMMDDHHMMSS_create_payment_allocations.rb`.

- [ ] **Step 2: Reemplazar el contenido de la migración**

Abrir el archivo generado y reemplazar su contenido por:

```ruby
class CreatePaymentAllocations < ActiveRecord::Migration[7.2]
  def change
    create_table :payment_allocations do |t|
      t.references :payment, null: false, foreign_key: true
      t.references :order,   null: false, foreign_key: true
      t.decimal :amount, precision: 10, scale: 2, null: false

      t.timestamps
    end

    add_index :payment_allocations, [ :payment_id, :order_id ], unique: true

    remove_index :payments, :order_id if index_exists?(:payments, :order_id)
    remove_column :payments, :order_id, :bigint
  end
end
```

- [ ] **Step 3: Correr la migración**

```bash
bin/rails db:migrate
```

Expected: `== CreatePaymentAllocations: migrated`. La tabla `payment_allocations` existe, `payments` ya no tiene `order_id`.

- [ ] **Step 4: Verificar el schema**

```bash
grep -A 8 "create_table \"payment_allocations\"" db/schema.rb
grep -A 12 "create_table \"payments\"" db/schema.rb
```

Expected: ver `payment_allocations` con columnas `payment_id`, `order_id`, `amount`, índice único compuesto. La definición de `payments` ya **no** debe contener `order_id`.

- [ ] **Step 5: Correr la suite — deben romperse tests, esperado**

```bash
bundle exec rspec
```

Expected: fallos masivos porque `Payment#order_id` ya no existe y `Order#outstanding_balance` queries hacen referencia a `payments.order_id`. Esto se arregla en las siguientes tasks. NO continuar arreglando suite manualmente — seguir el plan.

---

## Task 3: `PaymentAllocation` model — esqueleto + factory + asociaciones

**Files:**
- Create: `app/models/payment_allocation.rb`
- Create: `spec/factories/payment_allocations.rb`
- Test: `spec/models/payment_allocation_spec.rb`

- [ ] **Step 1: Crear el factory**

Crear `spec/factories/payment_allocations.rb`:

```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :payment_allocation do
    payment
    order
    amount { 100.0 }
  end
end
```

- [ ] **Step 2: Crear el spec inicial con asociaciones**

Crear `spec/models/payment_allocation_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentAllocation, type: :model do
  describe "associations" do
    it { should belong_to(:payment) }
    it { should belong_to(:order) }
  end
end
```

- [ ] **Step 3: Correr el spec — debe fallar por modelo inexistente**

```bash
bundle exec rspec spec/models/payment_allocation_spec.rb
```

Expected: `NameError: uninitialized constant PaymentAllocation`.

- [ ] **Step 4: Crear el modelo**

Crear `app/models/payment_allocation.rb`:

```ruby
# frozen_string_literal: true

class PaymentAllocation < ApplicationRecord
  belongs_to :payment
  belongs_to :order
end
```

- [ ] **Step 5: Correr el spec — asociaciones verdes**

```bash
bundle exec rspec spec/models/payment_allocation_spec.rb
```

Expected: 2 examples, 0 failures.

---

## Task 4: `PaymentAllocation` — validaciones de presencia y numericality

**Files:**
- Modify: `app/models/payment_allocation.rb`
- Test: `spec/models/payment_allocation_spec.rb`

- [ ] **Step 1: Agregar tests de validaciones básicas**

Dentro del bloque `RSpec.describe PaymentAllocation` en `spec/models/payment_allocation_spec.rb`, agregar después del bloque `associations`:

```ruby
  describe "validations" do
    it { should validate_presence_of(:amount) }
    it { should validate_numericality_of(:amount).is_greater_than(0) }
  end
```

- [ ] **Step 2: Correr los nuevos tests — deben fallar**

```bash
bundle exec rspec spec/models/payment_allocation_spec.rb -e "validations"
```

Expected: 2 fallos por validaciones no definidas.

- [ ] **Step 3: Agregar validaciones al modelo**

Reemplazar el contenido de `app/models/payment_allocation.rb` por:

```ruby
# frozen_string_literal: true

class PaymentAllocation < ApplicationRecord
  belongs_to :payment
  belongs_to :order

  validates :amount, presence: true, numericality: { greater_than: 0 }
end
```

- [ ] **Step 4: Correr los tests — verdes**

```bash
bundle exec rspec spec/models/payment_allocation_spec.rb
```

Expected: 4 examples, 0 failures.

---

## Task 5: `PaymentAllocation` — validar que `order` pertenezca al customer del payment

**Files:**
- Modify: `app/models/payment_allocation.rb`
- Test: `spec/models/payment_allocation_spec.rb`

- [ ] **Step 1: Agregar tests para `order_belongs_to_payment_customer`**

Dentro de `spec/models/payment_allocation_spec.rb`, después del bloque `validations`, agregar:

```ruby
  describe "order_belongs_to_payment_customer" do
    let!(:stock_location) { create(:stock_location) }
    let(:customer_a) { create(:customer, :with_credit) }
    let(:customer_b) { create(:customer, :with_credit) }
    let(:product) { create(:product, current_stock: 20, price_unit: 100) }

    let(:order_a) do
      Sales::CreateOrder.call(
        customer: customer_a,
        items: [ { product_id: product.id, quantity: 2, unit_price: 100 } ],
        order_type: "credit"
      ).record
    end

    let(:payment_a) { create(:payment, customer: customer_a) }

    it "is valid when order belongs to the payment customer" do
      allocation = build(:payment_allocation, payment: payment_a, order: order_a, amount: 100)
      expect(allocation).to be_valid
    end

    it "is invalid when order belongs to a different customer" do
      order_b = Sales::CreateOrder.call(
        customer: customer_b,
        items: [ { product_id: product.id, quantity: 1, unit_price: 100 } ],
        order_type: "credit"
      ).record

      allocation = build(:payment_allocation, payment: payment_a, order: order_b, amount: 50)
      expect(allocation).not_to be_valid
      expect(allocation.errors[:order]).to include("no pertenece al cliente del pago")
    end
  end
```

- [ ] **Step 2: Correr los tests — deben fallar**

```bash
bundle exec rspec spec/models/payment_allocation_spec.rb -e "order_belongs_to_payment_customer"
```

Expected: el segundo test falla porque sin la validación, la allocation es válida.

- [ ] **Step 3: Agregar la validación al modelo**

En `app/models/payment_allocation.rb`, reemplazar el contenido por:

```ruby
# frozen_string_literal: true

class PaymentAllocation < ApplicationRecord
  belongs_to :payment
  belongs_to :order

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validate :order_belongs_to_payment_customer

  private

  def order_belongs_to_payment_customer
    return if payment.nil? || order.nil?

    if order.customer_id != payment.customer_id
      errors.add(:order, "no pertenece al cliente del pago")
    end
  end
end
```

- [ ] **Step 4: Correr los tests — verdes**

```bash
bundle exec rspec spec/models/payment_allocation_spec.rb
```

Expected: todos verdes.

---

## Task 6: `PaymentAllocation` — validar `amount_within_order_outstanding_balance`

**Files:**
- Modify: `app/models/payment_allocation.rb`
- Test: `spec/models/payment_allocation_spec.rb`

**Contexto:** Esta validación replica el patrón de `Payment#amount_within_order_total` arreglado en feat_05. Usa `where.not(id: id)` para excluir la allocation actual y funcionar tanto en `create` como en `update`.

- [ ] **Step 1: Agregar tests para `amount_within_order_outstanding_balance`**

Dentro de `spec/models/payment_allocation_spec.rb`, después del bloque `order_belongs_to_payment_customer`, agregar:

```ruby
  describe "amount_within_order_outstanding_balance" do
    let!(:stock_location) { create(:stock_location) }
    let(:customer) { create(:customer, :with_credit) }
    let(:product) { create(:product, current_stock: 20, price_unit: 100) }
    let(:order) do
      Sales::CreateOrder.call(
        customer: customer,
        items: [ { product_id: product.id, quantity: 2, unit_price: 100 } ],
        order_type: "credit"
      ).record
    end
    let(:payment) { create(:payment, customer: customer, amount: 200) }

    it "is valid when amount equals exactly the remaining balance" do
      allocation = build(:payment_allocation, payment: payment, order: order, amount: 200)
      expect(allocation).to be_valid
    end

    it "is valid when amount is partial within remaining balance" do
      allocation = build(:payment_allocation, payment: payment, order: order, amount: 150)
      expect(allocation).to be_valid
    end

    it "is invalid when amount exceeds the order total (no other allocations)" do
      allocation = build(:payment_allocation, payment: payment, order: order, amount: 201)
      expect(allocation).not_to be_valid
      expect(allocation.errors[:amount].first).to match(/no puede exceder el saldo pendiente de la orden/)
    end

    context "when other allocations already exist for the same order" do
      let(:earlier_payment) { create(:payment, customer: customer, amount: 50) }
      before { create(:payment_allocation, payment: earlier_payment, order: order, amount: 50) }

      it "is valid when amount fits in the remaining balance" do
        allocation = build(:payment_allocation, payment: payment, order: order, amount: 150)
        expect(allocation).to be_valid
      end

      it "is invalid when amount exceeds the remaining balance" do
        allocation = build(:payment_allocation, payment: payment, order: order, amount: 151)
        expect(allocation).not_to be_valid
        expect(allocation.errors[:amount].first).to match(/no puede exceder el saldo pendiente de la orden/)
      end

      it "excludes itself on update (where.not(id: id))" do
        allocation = create(:payment_allocation, payment: payment, order: order, amount: 100)
        allocation.amount = 150  # bajo el remaining (200 - 50 = 150), inclusive
        expect(allocation).to be_valid
      end
    end
  end
```

- [ ] **Step 2: Correr los tests — deben fallar (validación no existe)**

```bash
bundle exec rspec spec/models/payment_allocation_spec.rb -e "amount_within_order_outstanding_balance"
```

Expected: fallos en los casos que verifican mensaje de error o no-validez.

- [ ] **Step 3: Agregar la validación al modelo**

Reemplazar `app/models/payment_allocation.rb` por:

```ruby
# frozen_string_literal: true

class PaymentAllocation < ApplicationRecord
  belongs_to :payment
  belongs_to :order

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validate :order_belongs_to_payment_customer
  validate :amount_within_order_outstanding_balance

  private

  def order_belongs_to_payment_customer
    return if payment.nil? || order.nil?

    if order.customer_id != payment.customer_id
      errors.add(:order, "no pertenece al cliente del pago")
    end
  end

  def amount_within_order_outstanding_balance
    return if amount.nil? || order.nil? || order.total_amount.nil?

    other_paid = PaymentAllocation
                   .where(order_id: order_id)
                   .where.not(id: id)
                   .sum(:amount)
    remaining = order.total_amount - other_paid

    if amount > remaining
      errors.add(:amount, "no puede exceder el saldo pendiente de la orden ($#{remaining})")
    end
  end
end
```

- [ ] **Step 4: Correr los tests del modelo completo**

```bash
bundle exec rspec spec/models/payment_allocation_spec.rb
```

Expected: todos verdes (alrededor de 11 examples).

- [ ] **Step 5: Lint**

```bash
bundle exec rubocop app/models/payment_allocation.rb spec/models/payment_allocation_spec.rb spec/factories/payment_allocations.rb
```

Expected: `no offenses detected`.

---

## Task 7: Refactor `Payment` model — quitar `belongs_to :order` y validación obsoleta

**Files:**
- Modify: `app/models/payment.rb`
- Test: `spec/models/payment_spec.rb`

**Contexto:** Tras Task 2, la columna `order_id` ya no existe en `payments`. El `belongs_to :order, optional: true` y la validación `amount_within_order_total` ya no aplican — su lógica se mudó a `PaymentAllocation`.

- [ ] **Step 1: Actualizar el spec de Payment**

Abrir `spec/models/payment_spec.rb`. Reemplazar el bloque `describe "associations"`:

```ruby
  describe "associations" do
    it { should belong_to(:customer) }
    it { should have_many(:allocations).class_name("PaymentAllocation") }
    it { should have_many(:orders).through(:allocations) }
  end
```

Borrar completamente el bloque `describe "amount_within_order_total" do ... end` (líneas ~34 a ~88, ambos inclusive). Borrar también cualquier referencia restante a `order:` en tests existentes (los specs de `scopes` y `factory` no usan `order:`, no necesitan tocarse).

- [ ] **Step 2: Correr el spec — deben fallar (asociaciones/validación viejas)**

```bash
bundle exec rspec spec/models/payment_spec.rb
```

Expected: fallos relacionados con `belongs_to :order` que sigue en el modelo y `amount_within_order_total` que sigue declarado.

- [ ] **Step 3: Actualizar el modelo Payment**

Reemplazar `app/models/payment.rb` por:

```ruby
# frozen_string_literal: true

class Payment < ApplicationRecord
  # Associations
  belongs_to :customer
  has_many :allocations, class_name: "PaymentAllocation", dependent: :destroy
  has_many :orders, through: :allocations

  # Constants
  PAYMENT_METHODS = %w[cash transfer check card].freeze

  # Validations
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :payment_method, presence: true, inclusion: { in: PAYMENT_METHODS }
  validates :payment_date, presence: true
  validate :customer_must_have_credit_account

  # Scopes
  scope :by_customer, ->(customer) { where(customer: customer) }
  scope :recent, -> { order(payment_date: :desc, created_at: :desc) }

  private

  def customer_must_have_credit_account
    return if customer.nil?

    unless customer.has_credit_account?
      errors.add(:customer, "must have credit account enabled")
    end
  end
end
```

- [ ] **Step 4: Correr el spec — verde**

```bash
bundle exec rspec spec/models/payment_spec.rb
```

Expected: todos los ejemplos verdes.

- [ ] **Step 5: Lint**

```bash
bundle exec rubocop app/models/payment.rb spec/models/payment_spec.rb
```

Expected: `no offenses detected`.

---

## Task 8: Refactor `Order` model — duplicado y `outstanding_balance` vía allocations

**Files:**
- Modify: `app/models/order.rb`
- Test: `spec/models/order_spec.rb`

**Contexto:** `Order` tiene un `has_many :payments, dependent: :destroy` duplicado (líneas 6 y 8). El refactor lo limpia y agrega `has_many :payment_allocations` + `has_many :payments, through: :payment_allocations`. `outstanding_balance` cambia para sumar `payment_allocations.sum(:amount)`.

- [ ] **Step 1: Actualizar los tests existentes de `outstanding_balance`**

Abrir `spec/models/order_spec.rb`. Localizar el bloque `describe '#outstanding_balance'`. Reemplazarlo por:

```ruby
  describe "#outstanding_balance" do
    let!(:stock_location) { create(:stock_location) }
    let(:customer) { create(:customer, :with_credit) }
    let(:product) { create(:product, current_stock: 20, price_unit: 100) }

    context "when order is immediate" do
      let(:order) do
        Sales::CreateOrder.call(
          customer: Customer.mostrador,
          items: [ { product_id: product.id, quantity: 1, unit_price: 100 } ],
          order_type: "immediate"
        ).record
      end

      it "returns 0 regardless of allocations" do
        expect(order.outstanding_balance).to eq(0)
      end
    end

    context "when order is cancelled" do
      let(:order) do
        result = Sales::CreateOrder.call(
          customer: customer,
          items: [ { product_id: product.id, quantity: 2, unit_price: 100 } ],
          order_type: "credit"
        )
        result.record.tap { |o| Sales::CancelOrder.call(order: o) }
      end

      it "returns 0" do
        expect(order.outstanding_balance).to eq(0)
      end
    end

    context "when order is credit with no allocations" do
      let(:order) do
        Sales::CreateOrder.call(
          customer: customer,
          items: [ { product_id: product.id, quantity: 2, unit_price: 100 } ],
          order_type: "credit"
        ).record
      end

      it "returns the full total_amount" do
        expect(order.outstanding_balance).to eq(200)
      end
    end

    context "when order has a partial allocation" do
      let(:order) do
        Sales::CreateOrder.call(
          customer: customer,
          items: [ { product_id: product.id, quantity: 2, unit_price: 100 } ],
          order_type: "credit",
          initial_payment: { amount: 50, payment_method: "cash" }
        ).record
      end

      it "returns total minus allocated amount" do
        expect(order.outstanding_balance).to eq(150)
      end
    end

    context "when order is fully allocated" do
      let(:order) do
        Sales::CreateOrder.call(
          customer: customer,
          items: [ { product_id: product.id, quantity: 2, unit_price: 100 } ],
          order_type: "credit",
          initial_payment: { amount: 200, payment_method: "cash" }
        ).record
      end

      it "returns 0" do
        expect(order.outstanding_balance).to eq(0)
      end
    end
  end
```

(Si el contexto "when order is cancelled" no existía antes, mantenerlo como agregado nuevo — cubre el branch `cancelled_status? → 0`.)

- [ ] **Step 2: Correr los tests — deben fallar**

```bash
bundle exec rspec spec/models/order_spec.rb -e "outstanding_balance"
```

Expected: fallos porque `outstanding_balance` aún suma `payments` (que ya no tiene `order_id` y tira excepción) y porque `Sales::CreateOrder` aún crea `Payment(order: ...)`.

- [ ] **Step 3: Actualizar el modelo Order**

Abrir `app/models/order.rb`. Localizar las dos líneas duplicadas:

```ruby
  has_many :payments, dependent: :destroy
  has_many :stock_movements, as: :reference, dependent: :nullify
  has_many :payments, dependent: :destroy
```

Reemplazar esas tres líneas (el bloque de `has_many` desde la primera `:payments` hasta la segunda) por:

```ruby
  has_many :payment_allocations, dependent: :destroy
  has_many :payments, through: :payment_allocations
  has_many :stock_movements, as: :reference, dependent: :nullify
```

Localizar el método `outstanding_balance` (alrededor de línea 65):

```ruby
  def outstanding_balance
    return 0 unless credit_order_type?
    return 0 if cancelled_status?

    total_amount - payments.sum(:amount)
  end
```

Reemplazarlo por:

```ruby
  def outstanding_balance
    return 0 unless credit_order_type?
    return 0 if cancelled_status?

    total_amount - payment_allocations.sum(:amount)
  end
```

- [ ] **Step 4: Correr los tests del modelo Order**

```bash
bundle exec rspec spec/models/order_spec.rb
```

Expected: el bloque de `outstanding_balance` aún falla — necesita Task 9 para que `initial_payment` cree allocations. Continuar.

- [ ] **Step 5: Lint**

```bash
bundle exec rubocop app/models/order.rb spec/models/order_spec.rb
```

Expected: `no offenses detected`.

---

## Task 9: Refactor `Sales::CreateOrder` — `initial_payment` crea Payment + Allocation

**Files:**
- Modify: `app/services/sales/create_order.rb`
- Test: `spec/services/sales/create_order_spec.rb`

- [ ] **Step 1: Actualizar tests existentes de `initial_payment`**

Abrir `spec/services/sales/create_order_spec.rb`. Buscar el bloque que testea `initial_payment` (ej. `context "with initial_payment"` o similar). Reemplazar/extender los tests para verificar Payment + PaymentAllocation:

```ruby
  context "with initial_payment on a credit order" do
    let!(:stock_location) { create(:stock_location) }
    let(:customer) { create(:customer, :with_credit) }
    let(:product) { create(:product, current_stock: 10, price_unit: 100) }

    it "creates a Payment tied to the customer" do
      result = described_class.call(
        customer: customer,
        items: [ { product_id: product.id, quantity: 2, unit_price: 100 } ],
        order_type: "credit",
        initial_payment: { amount: 150, payment_method: "cash" }
      )

      expect(result.success?).to be true
      payment = Payment.last
      expect(payment.customer_id).to eq(customer.id)
      expect(payment.amount).to eq(150)
      expect(payment.payment_method).to eq("cash")
    end

    it "creates a PaymentAllocation linking the payment to the new order" do
      result = described_class.call(
        customer: customer,
        items: [ { product_id: product.id, quantity: 2, unit_price: 100 } ],
        order_type: "credit",
        initial_payment: { amount: 150, payment_method: "cash" }
      )

      order = result.record
      allocation = order.payment_allocations.first
      expect(allocation).to be_present
      expect(allocation.amount).to eq(150)
      expect(allocation.payment_id).to eq(Payment.last.id)
    end

    it "results in order.outstanding_balance reflecting the allocation" do
      result = described_class.call(
        customer: customer,
        items: [ { product_id: product.id, quantity: 2, unit_price: 100 } ],
        order_type: "credit",
        initial_payment: { amount: 150, payment_method: "cash" }
      )

      expect(result.record.outstanding_balance).to eq(50)
    end
  end
```

Si ya existían tests con `order_id` o `payment.order`, borrarlos o reemplazarlos por los de arriba.

- [ ] **Step 2: Correr los tests — deben fallar**

```bash
bundle exec rspec spec/services/sales/create_order_spec.rb -e "initial_payment"
```

Expected: fallos porque `create_initial_payment` aún hace `Payment.create!(order: @order, ...)` con un atributo que no existe.

- [ ] **Step 3: Actualizar el servicio**

Abrir `app/services/sales/create_order.rb`. Localizar el método `create_initial_payment` (al final, alrededor de línea 184):

```ruby
    def create_initial_payment
      Payment.create!(
        customer: @customer,
        order: @order,
        amount: @initial_payment[:amount],
        payment_method: @initial_payment[:payment_method],
        payment_date: @sale_date
      )
    end
```

Reemplazarlo por:

```ruby
    def create_initial_payment
      payment = Payment.create!(
        customer: @customer,
        amount: @initial_payment[:amount],
        payment_method: @initial_payment[:payment_method],
        payment_date: @sale_date
      )

      PaymentAllocation.create!(
        payment: payment,
        order: @order,
        amount: @initial_payment[:amount]
      )
    end
```

- [ ] **Step 4: Correr los tests del servicio**

```bash
bundle exec rspec spec/services/sales/create_order_spec.rb
```

Expected: verde. El bloque completo del spec de `outstanding_balance` (Task 8) también debería pasar ahora.

- [ ] **Step 5: Correr el spec de Order**

```bash
bundle exec rspec spec/models/order_spec.rb
```

Expected: verde.

- [ ] **Step 6: Lint**

```bash
bundle exec rubocop app/services/sales/create_order.rb spec/services/sales/create_order_spec.rb
```

Expected: `no offenses detected`.

---

## Task 10: Refactor `Sales::CancelOrder` — destruir solo allocations

**Files:**
- Modify: `app/services/sales/cancel_order.rb`
- Test: `spec/services/sales/cancel_order_spec.rb`

**Contexto:** La cancelación de una orden destruye sus `payment_allocations`. Los `Payment` quedan vivos (conducta intencional descrita en _Known limitations_ del spec). El `current_balance` del cliente sigue descontando los pagos huérfanos.

- [ ] **Step 1: Actualizar tests existentes**

Abrir `spec/services/sales/cancel_order_spec.rb`. Localizar el bloque que valida que cancelar destruye payments. Reemplazarlo por:

```ruby
  describe "destroying associated allocations" do
    let!(:stock_location) { create(:stock_location) }
    let(:customer) { create(:customer, :with_credit) }
    let(:product) { create(:product, current_stock: 10, price_unit: 100) }
    let(:order) do
      Sales::CreateOrder.call(
        customer: customer,
        items: [ { product_id: product.id, quantity: 2, unit_price: 100 } ],
        order_type: "credit",
        initial_payment: { amount: 150, payment_method: "cash" }
      ).record
    end

    it "destroys the PaymentAllocations for the cancelled order" do
      expect(order.payment_allocations.count).to eq(1)

      described_class.call(order: order)

      expect(order.reload.payment_allocations.count).to eq(0)
    end

    it "keeps the Payment record alive (known limitation: orphaned payment)" do
      payment_id = order.payment_allocations.first.payment_id

      described_class.call(order: order)

      expect(Payment.find_by(id: payment_id)).to be_present
    end
  end
```

- [ ] **Step 2: Correr los tests — deben fallar**

```bash
bundle exec rspec spec/services/sales/cancel_order_spec.rb
```

Expected: el primer test pasa o falla dependiendo del estado actual (el servicio destruye `payments` que ya no tiene `order_id`); el test de "keeps the Payment alive" falla porque `@order.payments.destroy_all` los borra todos (via `through: :payment_allocations` borra Payments también).

- [ ] **Step 3: Actualizar el servicio**

Abrir `app/services/sales/cancel_order.rb`. Localizar el método `destroy_associated_payments`:

```ruby
    def destroy_associated_payments
      @order.payments.destroy_all
    end
```

Reemplazarlo (cambiar nombre y comportamiento) por:

```ruby
    def destroy_associated_allocations
      @order.payment_allocations.destroy_all
    end
```

Y en el bloque `call`, actualizar la línea que invoca al método:

```ruby
      ActiveRecord::Base.transaction do
        cancel_order
        reverse_stock_movements
        destroy_associated_allocations

        Result.new(success?: true, record: @order, errors: [])
      end
```

- [ ] **Step 4: Correr los tests**

```bash
bundle exec rspec spec/services/sales/cancel_order_spec.rb
```

Expected: verde.

- [ ] **Step 5: Lint**

```bash
bundle exec rubocop app/services/sales/cancel_order.rb spec/services/sales/cancel_order_spec.rb
```

Expected: `no offenses detected`.

---

## Task 11: `Payments::AllocatePayment` servicio — tests primero

**Files:**
- Create: `app/services/payments/allocate_payment.rb`
- Test: `spec/services/payments/allocate_payment_spec.rb`

- [ ] **Step 1: Crear el spec con todos los casos**

Crear `spec/services/payments/allocate_payment_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::AllocatePayment, type: :service do
  let!(:stock_location) { create(:stock_location) }
  let(:customer) { create(:customer, :with_credit) }
  let(:product) { create(:product, current_stock: 50, price_unit: 100) }

  let(:order_a) do
    Sales::CreateOrder.call(
      customer: customer,
      items: [ { product_id: product.id, quantity: 3, unit_price: 100 } ],
      order_type: "credit"
    ).record
  end

  let(:order_b) do
    Sales::CreateOrder.call(
      customer: customer,
      items: [ { product_id: product.id, quantity: 2, unit_price: 100 } ],
      order_type: "credit"
    ).record
  end

  describe ".call" do
    context "with invalid input" do
      it "fails when customer has no credit account" do
        retail = create(:customer, has_credit_account: false)
        result = described_class.call(
          customer: retail,
          payment_date: Date.today,
          allocations: [ { order_id: order_a.id, amount: 100, payment_method: "cash" } ]
        )
        expect(result.failure?).to be true
        expect(result.errors.join).to match(/cuenta corriente/i)
      end

      it "fails when allocations is empty" do
        result = described_class.call(
          customer: customer,
          payment_date: Date.today,
          allocations: []
        )
        expect(result.failure?).to be true
        expect(result.errors.join).to match(/al menos una orden/i)
      end

      it "fails when an order does not belong to the customer" do
        other_customer = create(:customer, :with_credit)
        foreign_order = Sales::CreateOrder.call(
          customer: other_customer,
          items: [ { product_id: product.id, quantity: 1, unit_price: 100 } ],
          order_type: "credit"
        ).record

        result = described_class.call(
          customer: customer,
          payment_date: Date.today,
          allocations: [ { order_id: foreign_order.id, amount: 50, payment_method: "cash" } ]
        )
        expect(result.failure?).to be true
        expect(result.errors.join).to match(/no pertenece/i)
      end

      it "fails when an order is not credit" do
        immediate = Sales::CreateOrder.call(
          customer: Customer.mostrador,
          items: [ { product_id: product.id, quantity: 1, unit_price: 100 } ],
          order_type: "immediate"
        ).record

        result = described_class.call(
          customer: customer,
          payment_date: Date.today,
          allocations: [ { order_id: immediate.id, amount: 50, payment_method: "cash" } ]
        )
        expect(result.failure?).to be true
      end

      it "fails when amount exceeds outstanding balance of an order" do
        result = described_class.call(
          customer: customer,
          payment_date: Date.today,
          allocations: [ { order_id: order_a.id, amount: order_a.total_amount + 1, payment_method: "cash" } ]
        )
        expect(result.failure?).to be true
        expect(result.errors.join).to match(/saldo pendiente/i)
      end

      it "fails when payment_method is invalid" do
        result = described_class.call(
          customer: customer,
          payment_date: Date.today,
          allocations: [ { order_id: order_a.id, amount: 50, payment_method: "bitcoin" } ]
        )
        expect(result.failure?).to be true
        expect(result.errors.join).to match(/método de pago/i)
      end
    end

    context "with valid input — single method" do
      it "creates one Payment grouping all allocations under that method" do
        expect {
          described_class.call(
            customer: customer,
            payment_date: Date.today,
            allocations: [
              { order_id: order_a.id, amount: 100, payment_method: "cash" },
              { order_id: order_b.id, amount: 80, payment_method: "cash" }
            ]
          )
        }.to change(Payment, :count).by(1)
         .and change(PaymentAllocation, :count).by(2)

        payment = Payment.last
        expect(payment.amount).to eq(180)
        expect(payment.payment_method).to eq("cash")
        expect(payment.allocations.pluck(:amount).sort).to eq([ 80, 100 ])
      end

      it "returns Result.success with the array of created Payments in record" do
        result = described_class.call(
          customer: customer,
          payment_date: Date.today,
          allocations: [ { order_id: order_a.id, amount: 100, payment_method: "cash" } ]
        )
        expect(result.success?).to be true
        expect(result.record).to be_an(Array)
        expect(result.record.size).to eq(1)
        expect(result.record.first).to be_a(Payment)
      end
    end

    context "with valid input — mixed methods" do
      it "creates one Payment per payment_method group" do
        expect {
          described_class.call(
            customer: customer,
            payment_date: Date.today,
            allocations: [
              { order_id: order_a.id, amount: 100, payment_method: "cash" },
              { order_id: order_b.id, amount: 80, payment_method: "transfer" }
            ]
          )
        }.to change(Payment, :count).by(2)
         .and change(PaymentAllocation, :count).by(2)

        cash_payment = Payment.find_by(payment_method: "cash")
        transfer_payment = Payment.find_by(payment_method: "transfer")
        expect(cash_payment.amount).to eq(100)
        expect(transfer_payment.amount).to eq(80)
      end
    end

    context "transaction safety" do
      it "rolls back everything when a later allocation fails" do
        bad_amount = order_b.total_amount + 1
        expect {
          described_class.call(
            customer: customer,
            payment_date: Date.today,
            allocations: [
              { order_id: order_a.id, amount: 100, payment_method: "cash" },
              { order_id: order_b.id, amount: bad_amount, payment_method: "cash" }
            ]
          )
        }.to change(Payment, :count).by(0)
         .and change(PaymentAllocation, :count).by(0)
      end
    end

    context "notes" do
      it "saves the notes on every created Payment" do
        described_class.call(
          customer: customer,
          payment_date: Date.today,
          notes: "Pago semanal",
          allocations: [
            { order_id: order_a.id, amount: 100, payment_method: "cash" },
            { order_id: order_b.id, amount: 80, payment_method: "transfer" }
          ]
        )
        expect(Payment.pluck(:notes).uniq).to eq([ "Pago semanal" ])
      end
    end
  end
end
```

- [ ] **Step 2: Correr el spec — fallos por servicio inexistente**

```bash
bundle exec rspec spec/services/payments/allocate_payment_spec.rb
```

Expected: `NameError: uninitialized constant Payments::AllocatePayment` o equivalente.

- [ ] **Step 3: Crear el servicio**

Crear `app/services/payments/allocate_payment.rb`:

```ruby
# frozen_string_literal: true

module Payments
  class AllocatePayment
    def self.call(customer:, payment_date:, allocations:, notes: nil)
      new(
        customer: customer,
        payment_date: payment_date,
        allocations: allocations,
        notes: notes
      ).call
    end

    def initialize(customer:, payment_date:, allocations:, notes: nil)
      @customer = customer
      @payment_date = payment_date || Date.today
      @notes = notes
      @allocations = Array(allocations).map { |row| row.to_h.symbolize_keys }
    end

    def call
      validate_params

      payments = []
      ActiveRecord::Base.transaction do
        grouped_by_method.each do |method, rows|
          total = rows.sum { |r| r[:amount].to_f }
          payment = Payment.create!(
            customer: @customer,
            amount: total,
            payment_method: method,
            payment_date: @payment_date,
            notes: @notes
          )

          rows.each do |row|
            PaymentAllocation.create!(
              payment: payment,
              order_id: row[:order_id],
              amount: row[:amount].to_f
            )
          end

          payments << payment
        end

        Result.new(success?: true, record: payments, errors: [])
      end
    rescue ValidationError => e
      Result.new(success?: false, record: nil, errors: [ e.message ])
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, record: nil, errors: e.record.errors.full_messages)
    rescue StandardError => e
      Rails.logger.error("Error in Payments::AllocatePayment: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      Result.new(success?: false, record: nil, errors: [ "Error registrando el cobro" ])
    end

    private

    class ValidationError < StandardError; end

    def validate_params
      raise ValidationError, "Customer is required" if @customer.nil?

      unless @customer.has_credit_account?
        raise ValidationError, "El cliente no tiene cuenta corriente habilitada"
      end

      raise ValidationError, "Debe incluir al menos una orden" if @allocations.empty?

      @allocations.each do |row|
        amount = row[:amount].to_f
        raise ValidationError, "El monto debe ser mayor a cero" if amount <= 0

        unless Payment::PAYMENT_METHODS.include?(row[:payment_method])
          raise ValidationError, "Método de pago inválido: #{row[:payment_method]}"
        end

        order = Order.find_by(id: row[:order_id])
        raise ValidationError, "Orden no encontrada (id #{row[:order_id]})" if order.nil?

        if order.customer_id != @customer.id
          raise ValidationError, "La orden ##{order.id} no pertenece al cliente"
        end

        unless order.credit_order_type? && order.confirmed_status?
          raise ValidationError, "La orden ##{order.id} no es una venta a crédito confirmada"
        end

        if amount > order.outstanding_balance
          raise ValidationError, "El monto excede el saldo pendiente de la orden ##{order.id} ($#{order.outstanding_balance})"
        end
      end
    end

    def grouped_by_method
      @allocations.group_by { |row| row[:payment_method] }
    end
  end
end
```

- [ ] **Step 4: Correr el spec del servicio**

```bash
bundle exec rspec spec/services/payments/allocate_payment_spec.rb
```

Expected: todos los ejemplos verdes.

- [ ] **Step 5: Correr la suite completa hasta aquí**

```bash
bundle exec rspec
```

Expected: verde (los specs de modelos/servicios; las vistas todavía no están, pero no hay request specs nuevos).

- [ ] **Step 6: Lint**

```bash
bundle exec rubocop app/services/payments/allocate_payment.rb spec/services/payments/allocate_payment_spec.rb
```

Expected: `no offenses detected`.

---

## Task 12: Refactor `Web::Customers::PaymentsController` — usar `AllocatePayment`

**Files:**
- Modify: `app/controllers/web/customers/payments_controller.rb`

- [ ] **Step 1: Reemplazar el controller completo**

Reemplazar el contenido de `app/controllers/web/customers/payments_controller.rb` por:

```ruby
# frozen_string_literal: true

module Web
  module Customers
    class PaymentsController < ApplicationController
      before_action :set_customer

      def new
        authorize Payment.new(customer: @customer), :new?
        @pending_orders = @customer.orders
                                    .credit
                                    .where(status: "confirmed")
                                    .includes(:payment_allocations)
                                    .order(:created_at)
                                    .select { |o| o.outstanding_balance > 0 }
      end

      def create
        authorize Payment.new(customer: @customer), :new?

        result = Payments::AllocatePayment.call(
          customer: @customer,
          payment_date: params[:payment_date].presence || Date.today,
          notes: params[:notes],
          allocations: parsed_allocations
        )

        if result.success?
          total = result.record.sum(&:amount)
          orders_count = result.record.sum { |p| p.allocations.size }
          redirect_to web_customer_path(@customer),
                      notice: "Cobro de $#{total.to_i} registrado sobre #{orders_count} #{'orden'.pluralize(orders_count)}."
        else
          @pending_orders = @customer.orders
                                      .credit
                                      .where(status: "confirmed")
                                      .includes(:payment_allocations)
                                      .order(:created_at)
                                      .select { |o| o.outstanding_balance > 0 }
          flash.now[:alert] = result.errors.join(", ")
          render :new, status: :unprocessable_entity
        end
      end

      private

      def set_customer
        @customer = Customer.find(params[:customer_id])
      end

      def parsed_allocations
        Array(params[:allocations]).filter_map do |_idx, row|
          next if row[:include] != "1"
          next if row[:amount].blank? || row[:amount].to_f <= 0

          {
            order_id: row[:order_id],
            amount: row[:amount].to_f,
            payment_method: row[:payment_method]
          }
        end
      end
    end
  end
end
```

**Nota:** `params[:allocations]` viene como hash indexado por número (`{"0" => {...}, "1" => {...}}`) cuando el form usa `name="allocations[0][order_id]"`. `filter_map` itera y omite las filas no tildadas (`include != "1"`) o con monto cero.

- [ ] **Step 2: Lint**

```bash
bundle exec rubocop app/controllers/web/customers/payments_controller.rb
```

Expected: `no offenses detected`.

- [ ] **Step 3: Verificar que no hay regresión hasta aquí**

```bash
bundle exec rspec
```

Expected: verde. Los specs existentes del controller (si existen) podrían fallar — se actualizan/crean en Task 16.

---

## Task 13: Crear Stimulus controller para el form

**Files:**
- Create: `app/javascript/controllers/payment_allocation_controller.js`

- [ ] **Step 1: Crear el controller**

Crear `app/javascript/controllers/payment_allocation_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

// Maneja la interactividad del form de cobro multi-orden:
// - Tildar checkbox: habilita inputs de la fila, pre-rellena amount con el pending
// - Destildar: deshabilita inputs, limpia valores
// - Cualquier cambio: recalcula cobrando_ahora / saldo_restante / órdenes_incluidas
export default class extends Controller {
  static targets = ["row", "totalCharging", "remainingBalance", "selectedCount", "submitButton"]
  static values = { totalDebt: Number, totalOrdersCount: Number }

  connect() {
    this.updateSummary()
  }

  toggleRow(event) {
    const row = event.target.closest("[data-payment-allocation-target='row']")
    const amountInput = row.querySelector("[data-role='amount-input']")
    const methodSelect = row.querySelector("[data-role='method-select']")
    const pending = parseFloat(row.dataset.pending)

    if (event.target.checked) {
      amountInput.disabled = false
      methodSelect.disabled = false
      amountInput.value = pending.toFixed(2)
      row.classList.remove("opacity-60")
    } else {
      amountInput.disabled = true
      methodSelect.disabled = true
      amountInput.value = ""
      row.classList.add("opacity-60")
    }

    this.updateSummary()
  }

  recalc() {
    this.updateSummary()
  }

  updateSummary() {
    let charging = 0
    let selected = 0

    this.rowTargets.forEach(row => {
      const checkbox = row.querySelector("[data-role='include-checkbox']")
      const amountInput = row.querySelector("[data-role='amount-input']")
      if (checkbox.checked && amountInput.value) {
        const v = parseFloat(amountInput.value) || 0
        charging += v
        if (v > 0) selected += 1
      }
    })

    const remaining = this.totalDebtValue - charging

    this.totalChargingTarget.textContent = this.formatMoney(charging)
    this.remainingBalanceTarget.textContent = this.formatMoney(remaining)
    this.selectedCountTarget.textContent = selected

    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.disabled = selected === 0
    }
  }

  formatMoney(value) {
    return "$" + Math.round(value).toLocaleString("es-AR")
  }
}
```

- [ ] **Step 2: Verificar que el archivo está donde Rails lo busca**

```bash
ls app/javascript/controllers/
```

Expected: ver `payment_allocation_controller.js` listado junto a los demás controllers existentes. Stimulus los autocarga vía `app/javascript/controllers/index.js` (importmap o jsbundling). Si el index.js es manual, agregar la línea:

```bash
grep -l "payment_allocation_controller" app/javascript/controllers/index.js 2>/dev/null || echo "REVISAR si index.js necesita registro manual"
```

Si el comando dice REVISAR, abrir `app/javascript/controllers/index.js` y agregar el import siguiendo el patrón existente (típico Rails 7.2 con `stimulus:manifest:update`):

```bash
bin/rails stimulus:manifest:update
```

Expected: el manifest se regenera incluyendo el nuevo controller.

---

## Task 14: Nueva vista — `customers/payments/new.html.haml`

**Files:**
- Modify: `app/views/web/customers/payments/new.html.haml`

- [ ] **Step 1: Reemplazar el contenido completo de la vista**

Reemplazar `app/views/web/customers/payments/new.html.haml` por:

```haml
- content_for :page_title, "Registrar Cobro"

- payment_method_options = [ [ "Efectivo", "cash" ], [ "Transferencia", "transfer" ], [ "Cheque", "check" ], [ "Tarjeta", "card" ] ]
- total_debt = @customer.current_balance

.container.mx-auto.px-6.py-6

  -# Header
  .flex.items-center.gap-4.mb-2
    = link_to web_customer_path(@customer), class: "text-slate-600 hover:text-slate-900" do
      %span.text-xl ←
    %h1.text-3xl.font-bold.text-slate-900 Registrar Cobro
  %p.text-sm.text-slate-500.mb-6.ml-9= "#{@customer.name} · Cuenta corriente"

  -# Errores
  - if flash[:alert]
    .bg-red-50.border-l-4.border-red-500.p-4.rounded-lg.mb-6
      %p.text-sm.text-red-700= flash[:alert]

  - if @pending_orders.blank?
    -# Empty state: sin credit account o sin órdenes pendientes
    .bg-white.border.border-slate-200.rounded-lg.p-16.text-center
      .inline-flex.w-20.h-20.rounded-full.bg-slate-100.items-center.justify-center.text-4xl.mb-4
        - if @customer.has_credit_account?
          ✓
        - else
          ⊘
      - if !@customer.has_credit_account?
        %h3.text-xl.font-bold.text-slate-900.mb-2 Sin cuenta corriente
        %p.text-slate-500 Este cliente no tiene cuenta corriente habilitada.
        .flex.items-center.justify-center.gap-3.mt-6
          = link_to "← Volver", web_customer_path(@customer), class: "px-4 py-2 border border-slate-300 text-slate-700 text-sm font-semibold rounded-lg hover:bg-slate-50 transition-colors"
          - if policy(@customer).edit?
            = link_to "Editar cliente", edit_web_customer_path(@customer), class: "px-4 py-2 bg-slate-700 hover:bg-slate-800 text-white text-sm font-semibold rounded-lg transition-colors"
      - else
        %h3.text-xl.font-bold.text-slate-900.mb-2 Todo al día
        %p.text-slate-500 Este cliente no tiene órdenes con saldo pendiente.
        = link_to "← Volver al cliente", web_customer_path(@customer), class: "inline-flex items-center gap-2 mt-6 px-4 py-2 border border-slate-300 text-slate-700 text-sm font-semibold rounded-lg hover:bg-slate-50 transition-colors"

  - else
    = form_with url: web_customer_payments_path(@customer), method: :post, local: true, data: { controller: "payment-allocation", "payment-allocation-total-debt-value": total_debt.to_s } do

      -# Card resumen
      .bg-white.border.border-slate-200.rounded-xl.p-5.mb-4
        .flex.gap-8
          .flex-shrink-0
            %p.text-xs.text-slate-500.uppercase.tracking-wider.font-medium Deuda total
            %p.text-2xl.font-bold.text-slate-900.mt-1= currency_ar_int(total_debt)
          .border-l.border-slate-200.pl-8
            %p.text-xs.text-slate-500.uppercase.tracking-wider.font-medium Cobrando ahora
            %p.text-2xl.font-bold.text-slate-900.mt-1{ data: { "payment-allocation-target": "totalCharging" } } $0
          .border-l.border-slate-200.pl-8
            %p.text-xs.text-slate-500.uppercase.tracking-wider.font-medium Saldo restante
            %p.text-2xl.font-bold.text-amber-600.mt-1{ data: { "payment-allocation-target": "remainingBalance" } }= currency_ar_int(total_debt)
          .border-l.border-slate-200.pl-8.ml-auto
            %p.text-xs.text-slate-500.uppercase.tracking-wider.font-medium Órdenes incluidas
            %p.text-2xl.font-bold.text-slate-900.mt-1
              %span{ data: { "payment-allocation-target": "selectedCount" } } 0
              %span.text-sm.text-slate-400.font-medium= " de #{@pending_orders.size}"

      -# Tabla de órdenes
      .bg-white.border.border-slate-200.rounded-xl.p-6.mb-4
        %h3.text-base.font-semibold.text-slate-900.mb-4 Órdenes pendientes

        .overflow-x-auto
          %table.min-w-full
            %thead
              %tr.border-b.border-slate-200
                %th.px-2.py-2.w-10
                %th.px-2.py-2.text-left.text-xs.font-medium.text-slate-500.uppercase.tracking-wider Factura
                %th.px-2.py-2.text-left.text-xs.font-medium.text-slate-500.uppercase.tracking-wider Fecha
                %th.px-2.py-2.text-center.text-xs.font-medium.text-slate-500.uppercase.tracking-wider Ítems
                %th.px-2.py-2.text-right.text-xs.font-medium.text-slate-500.uppercase.tracking-wider Total
                %th.px-2.py-2.text-right.text-xs.font-medium.text-slate-500.uppercase.tracking-wider Cobrado
                %th.px-2.py-2.text-right.text-xs.font-medium.text-slate-500.uppercase.tracking-wider Pendiente
                %th.px-2.py-2.text-right.text-xs.font-medium.text-slate-500.uppercase.tracking-wider.w-32 Cobrar
                %th.px-2.py-2.text-left.text-xs.font-medium.text-slate-500.uppercase.tracking-wider.w-40 Método

            %tbody
              - @pending_orders.each_with_index do |order, idx|
                - paid_so_far = order.payment_allocations.sum(:amount)
                - pending = order.outstanding_balance
                %tr.border-b.border-slate-100.opacity-60{ data: { "payment-allocation-target": "row", "pending": pending } }
                  = hidden_field_tag "allocations[#{idx}][order_id]", order.id

                  %td.px-2.py-3.text-center
                    = check_box_tag "allocations[#{idx}][include]", "1", false,
                        class: "w-4 h-4 rounded border-slate-300",
                        data: { "role": "include-checkbox", action: "change->payment-allocation#toggleRow" }
                  %td.px-2.py-3.text-sm.font-semibold.text-slate-900= "##{order.id}"
                  %td.px-2.py-3.text-sm.text-slate-600= l(order.sale_date || order.created_at.to_date, format: :default)
                  %td.px-2.py-3.text-center.text-sm
                    %span.text-slate-700.underline.decoration-dotted= "#{order.order_items.size} productos"
                  %td.px-2.py-3.text-right.text-sm.font-semibold.text-slate-900= currency_ar_int(order.total_amount)
                  %td.px-2.py-3.text-right.text-sm.text-slate-600= currency_ar_int(paid_so_far)
                  %td.px-2.py-3.text-right.text-sm.font-semibold.text-amber-600= currency_ar_int(pending)
                  %td.px-2.py-3.text-right
                    = number_field_tag "allocations[#{idx}][amount]", nil,
                        step: "0.01", min: "0",
                        disabled: true,
                        class: "w-28 px-2 py-1.5 text-right text-sm font-semibold border border-slate-300 rounded-lg focus:ring-2 focus:ring-slate-500 focus:border-transparent disabled:bg-slate-50 disabled:text-slate-400",
                        data: { "role": "amount-input", action: "input->payment-allocation#recalc" }
                  %td.px-2.py-3
                    = select_tag "allocations[#{idx}][payment_method]",
                        options_for_select(payment_method_options, "cash"),
                        disabled: true,
                        class: "w-36 px-2 py-1.5 text-sm border border-slate-300 rounded-lg disabled:bg-slate-50 disabled:text-slate-400",
                        data: { "role": "method-select" }

        %p.text-xs.text-slate-400.italic.mt-3
          Tildá una orden y el monto se rellena con el saldo pendiente. Editalo si es pago parcial. "N productos" abrirá un modal con el detalle (futura mejora).

      -# Footer: fecha + notas + submit
      .bg-white.border.border-slate-200.rounded-xl.p-5.flex.items-end.gap-4
        %div
          %label.block.text-sm.text-slate-700.font-medium.mb-2 Fecha del cobro
          = date_field_tag :payment_date, Date.today,
              class: "border border-slate-300 rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-slate-500"
        .flex-1
          %label.block.text-sm.text-slate-700.font-medium.mb-2 Notas (opcional)
          = text_field_tag :notes, "",
              placeholder: "Referencia, comentarios…",
              class: "w-full border border-slate-300 rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-slate-500"
        .flex.gap-2
          = link_to "Cancelar", web_customer_path(@customer), class: "px-5 py-2.5 border border-slate-300 text-slate-700 text-sm font-semibold rounded-lg hover:bg-slate-50 transition-colors"
          = submit_tag "Registrar Cobro",
              class: "px-6 py-2.5 bg-slate-700 hover:bg-slate-800 text-white text-sm font-semibold rounded-lg disabled:bg-slate-300 disabled:cursor-not-allowed transition-colors",
              data: { "payment-allocation-target": "submitButton" },
              disabled: true
```

- [ ] **Step 2: Correr la suite — no debe haber regresiones**

```bash
bundle exec rspec
```

Expected: verde.

---

## Task 15: Actualizar `orders/show.html.haml` y `customers/show.html.haml` para leer vía allocations

**Files:**
- Modify: `app/views/web/orders/show.html.haml`
- Modify: `app/views/web/customers/show.html.haml`

- [ ] **Step 1: Actualizar `orders/show.html.haml` — sección "Pagos de esta Venta"**

Abrir `app/views/web/orders/show.html.haml`, localizar el bloque alrededor de la línea 286:

```haml
            - order_payments = @order.payments.order(payment_date: :asc)
            - if order_payments.any?
              .space-y-2.mb-3
                - order_payments.each do |p|
                  .flex.justify-between.items-center.text-sm
                    %span.text-gray-500= l(p.payment_date, format: :default)
                    %span.font-medium.text-emerald-700= currency_ar(p.amount)

              .border-t.border-gray-100.pt-2.space-y-1
                .flex.justify-between.text-sm
                  %span.text-gray-600 Total cobrado
                  %span.font-medium.text-gray-900= currency_ar(order_payments.sum(:amount))
```

Reemplazarlo por (usa `payment_allocations` para sumar la porción asignada a esta orden, no el total del Payment):

```haml
            - allocations = @order.payment_allocations.includes(:payment).joins(:payment).order("payments.payment_date ASC")
            - if allocations.any?
              .space-y-2.mb-3
                - allocations.each do |a|
                  .flex.justify-between.items-center.text-sm
                    %span.text-gray-500= l(a.payment.payment_date, format: :default)
                    %span.font-medium.text-emerald-700= currency_ar(a.amount)

              .border-t.border-gray-100.pt-2.space-y-1
                .flex.justify-between.text-sm
                  %span.text-gray-600 Total cobrado
                  %span.font-medium.text-gray-900= currency_ar(allocations.sum(:amount))
```

- [ ] **Step 2: Verificar el controller de orders precarga allocations**

Abrir `app/controllers/web/orders_controller.rb`, localizar la acción `show`. Asegurar que el `includes` contenga `payment_allocations`:

```ruby
    def show
      @order = Order.includes(order_items: :product, stock_movements: [ :product, :stock_location ], payment_allocations: :payment).find(params[:id])
    end
```

Si el código actual incluía `:payments`, reemplazar por `payment_allocations: :payment`.

- [ ] **Step 3: Actualizar `customers/show.html.haml` — columna Cobrado**

Abrir `app/views/web/customers/show.html.haml`, localizar la línea ~105:

```haml
                    %td.px-3.py-2.whitespace-nowrap.text-right.text-sm.text-emerald-700
                      = currency_ar_int(order.payments.map(&:amount).sum)
```

Reemplazar por:

```haml
                    %td.px-3.py-2.whitespace-nowrap.text-right.text-sm.text-emerald-700
                      = currency_ar_int(order.payment_allocations.sum(:amount))
```

- [ ] **Step 4: Verificar `customers_controller.rb` precarga allocations**

Abrir `app/controllers/web/customers_controller.rb`, en la acción `show`, cambiar `includes(:payments)` por `includes(:payment_allocations)` en la query de `@credit_orders`:

```ruby
    def show
      authorize @customer
      @credit_orders = @customer.orders
                                .where(order_type: "credit")
                                .where.not(status: "cancelled")
                                .includes(:payment_allocations)
                                .order(created_at: :desc)
      @payments = @customer.payments.order(payment_date: :desc)
      @current_balance = @customer.current_balance
    end
```

- [ ] **Step 5: Correr la suite — no regresiones**

```bash
bundle exec rspec
```

Expected: verde.

- [ ] **Step 6: Lint**

```bash
bundle exec rubocop app/controllers/web/orders_controller.rb app/controllers/web/customers_controller.rb
```

Expected: `no offenses detected`.

---

## Task 16: Request specs para el nuevo flujo de pago

**Files:**
- Create: `spec/requests/web/customers/payments_spec.rb`

- [ ] **Step 1: Crear el spec**

Crear `spec/requests/web/customers/payments_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Web::Customers::Payments", type: :request do
  let!(:stock_location) { create(:stock_location) }
  let(:admin) { create(:user, role: "admin") }
  let(:customer) { create(:customer, :with_credit) }
  let(:product) { create(:product, current_stock: 50, price_unit: 100) }

  before { sign_in admin }

  describe "GET /web/customers/:id/payments/new" do
    context "when customer has pending credit orders" do
      before do
        Sales::CreateOrder.call(
          customer: customer,
          items: [ { product_id: product.id, quantity: 2, unit_price: 100 } ],
          order_type: "credit"
        )
      end

      it "returns 200 and renders the form" do
        get new_web_customer_payment_path(customer)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Registrar Cobro")
        expect(response.body).to include("Órdenes pendientes")
      end
    end

    context "when customer has no credit account" do
      let(:no_credit_customer) { create(:customer, has_credit_account: false) }

      it "renders the empty state for no credit account" do
        get new_web_customer_payment_path(no_credit_customer)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Sin cuenta corriente")
      end
    end

    context "when customer has no pending orders" do
      it "renders the empty state for all paid up" do
        get new_web_customer_payment_path(customer)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Todo al día")
      end
    end
  end

  describe "POST /web/customers/:id/payments" do
    let!(:order_a) do
      Sales::CreateOrder.call(
        customer: customer,
        items: [ { product_id: product.id, quantity: 2, unit_price: 100 } ],
        order_type: "credit"
      ).record
    end

    let!(:order_b) do
      Sales::CreateOrder.call(
        customer: customer,
        items: [ { product_id: product.id, quantity: 3, unit_price: 100 } ],
        order_type: "credit"
      ).record
    end

    context "with valid single-method input" do
      it "creates one Payment and two Allocations, then redirects to customer show" do
        expect {
          post web_customer_payments_path(customer), params: {
            payment_date: Date.today.iso8601,
            notes: "Pago semanal",
            allocations: {
              "0" => { order_id: order_a.id, include: "1", amount: "200", payment_method: "cash" },
              "1" => { order_id: order_b.id, include: "1", amount: "150", payment_method: "cash" }
            }
          }
        }.to change(Payment, :count).by(1)
         .and change(PaymentAllocation, :count).by(2)

        expect(response).to redirect_to(web_customer_path(customer))
        follow_redirect!
        expect(response.body).to include("Cobro de $350")
      end
    end

    context "with mixed methods" do
      it "creates one Payment per method group" do
        expect {
          post web_customer_payments_path(customer), params: {
            allocations: {
              "0" => { order_id: order_a.id, include: "1", amount: "200", payment_method: "cash" },
              "1" => { order_id: order_b.id, include: "1", amount: "150", payment_method: "transfer" }
            }
          }
        }.to change(Payment, :count).by(2)
         .and change(PaymentAllocation, :count).by(2)
      end
    end

    context "with unchecked rows" do
      it "ignores rows with include != '1'" do
        expect {
          post web_customer_payments_path(customer), params: {
            allocations: {
              "0" => { order_id: order_a.id, include: "1", amount: "200", payment_method: "cash" },
              "1" => { order_id: order_b.id, include: "0", amount: "", payment_method: "cash" }
            }
          }
        }.to change(Payment, :count).by(1)
         .and change(PaymentAllocation, :count).by(1)
      end
    end

    context "with invalid input — amount exceeds outstanding" do
      it "re-renders the form with an error and creates nothing" do
        expect {
          post web_customer_payments_path(customer), params: {
            allocations: {
              "0" => { order_id: order_a.id, include: "1", amount: "9999", payment_method: "cash" }
            }
          }
        }.to change(Payment, :count).by(0)
         .and change(PaymentAllocation, :count).by(0)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to match(/saldo pendiente/i)
      end
    end

    context "with no rows checked" do
      it "returns an error" do
        post web_customer_payments_path(customer), params: {
          allocations: {
            "0" => { order_id: order_a.id, include: "0", amount: "0", payment_method: "cash" }
          }
        }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to match(/al menos una orden/i)
      end
    end
  end
end
```

- [ ] **Step 2: Correr el spec**

```bash
bundle exec rspec spec/requests/web/customers/payments_spec.rb
```

Expected: todos verdes. Si alguno falla, leer el error y comparar con la implementación del controller (Task 12) y el servicio (Task 11).

- [ ] **Step 3: Correr la suite completa**

```bash
bundle exec rspec
```

Expected: toda la suite verde.

- [ ] **Step 4: Lint**

```bash
bundle exec rubocop spec/requests/web/customers/payments_spec.rb
```

Expected: `no offenses detected`.

---

## Task 17: Actualizar `WORKING_CONTEXT.md` y `DEVELOPMENT_GUIDE.md`

**Files:**
- Modify: `WORKING_CONTEXT.md`
- Modify: `docs/DEVELOPMENT_GUIDE.md`

- [ ] **Step 1: Actualizar `WORKING_CONTEXT.md`, sección "Customer account payments"**

Localizar la sección `### Customer account payments` y reemplazar las bullets que mencionan `order_id` en `Payment` por:

```markdown
* **`PaymentAllocation`** join entre `Payment` y `Order` (`payment_allocations(payment_id, order_id, amount)`). Un Payment representa un tender (entrega física con un método único); sus allocations distribuyen ese monto sobre una o varias órdenes. Invariante: `payment.amount == SUM(allocations.amount)`.
* **`Payments::AllocatePayment`** (servicio nuevo) recibe `customer:, payment_date:, notes:, allocations: [{order_id:, amount:, payment_method:}]`, agrupa por `payment_method` y crea un `Payment` por grupo + sus `PaymentAllocation`s en una transacción. Reemplaza el uso anterior de `Payments::RegisterPayment` desde el web.
* **`Sales::CreateOrder`** con `initial_payment:` crea un `Payment` + 1 `PaymentAllocation` apuntando a la nueva orden.
* **`Sales::CancelOrder`** destruye las `PaymentAllocation` de la orden cancelada (`@order.payment_allocations.destroy_all`); los `Payment` quedan vivos (known limitation — pueden quedar huérfanos sin asignación).
* **`Order#outstanding_balance`** = `total_amount - payment_allocations.sum(:amount)` cuando es credit + confirmed; `0` para immediate o cancelled.
* **`Customer#current_balance`** suma `total_amount` de credit orders confirmadas y resta `payments.sum(:amount)` (a nivel de tender — sin tocar allocations).
* **`Web::Customers::PaymentsController`** ahora muestra una tabla con todas las órdenes pendientes; cada fila tiene checkbox de inclusión, monto editable, y método de pago propio. El submit POST recibe `params[:allocations]` indexado y delega en `Payments::AllocatePayment`.
* **`payments` table** ya no tiene la columna `order_id` — la relación vive en `payment_allocations`.
```

Borrar las bullets viejas correspondientes (las que decían "Los `Payment` pueden estar atados a una `Order`", "`Order#outstanding_balance` = `total_amount - order.payments.sum(:amount)`", `Payment#amount_within_order_total`, etc.).

- [ ] **Step 2: Actualizar `WORKING_CONTEXT.md`, sección "Web surface" (línea sobre Customers)**

Localizar la bullet de Customers; agregar mención al nuevo flujo:

```markdown
* **Customers**: index/show/new/create/edit/update; **`debtors`** collection → lista de clientes con balance > 0 ordenada por deuda; nested **`payments`** new/create → `Payments::AllocatePayment` (módulo `Web::Customers`); el form de cobro permite distribuir un pago en una o varias órdenes con método independiente por fila.
```

- [ ] **Step 3: Actualizar `WORKING_CONTEXT.md`, sección "Active services"**

En la lista de Payments, reemplazar `Payments::RegisterPayment` por `Payments::AllocatePayment`. Mantener `RegisterPayment` solo si todavía hay callers — verificar:

```bash
grep -rn "Payments::RegisterPayment" app/ lib/ 2>/dev/null
```

Si no hay callers, mover `Payments::RegisterPayment` a la sección "Present in codebase but not wired".

- [ ] **Step 4: Actualizar `docs/DEVELOPMENT_GUIDE.md`, sección Payments (línea 137-141)**

Reemplazar:

```markdown
### Payments

* Payments are global (not tied to a specific sale)
* Customer balance = credit sales - payments
```

Por:

```markdown
### Payments

* `Payment` representa un tender — entrega física de dinero con un método único (cash/transfer/check/card)
* Un `Payment` se asigna a una o más `Order`s vía `PaymentAllocation`s (`payment_allocations(payment_id, order_id, amount)`)
* Invariante: `payment.amount == SUM(allocations.amount)` — garantizada por `Payments::AllocatePayment`
* `Order#outstanding_balance` = `total_amount - allocations.sum(:amount)` (solo credit + confirmed)
* `Customer#current_balance` = `SUM(credit_orders.total_amount) - SUM(payments.amount)` — los allocations no intervienen en el balance del cliente
```

- [ ] **Step 5: Verificar los diffs**

```bash
git diff WORKING_CONTEXT.md docs/DEVELOPMENT_GUIDE.md
```

Expected: solo cambios coherentes con las modificaciones anteriores; ninguna sección inesperada tocada.

---

## Task 18: Verificación final + commit único

**Files:** ninguno (commit).

- [ ] **Step 1: Suite completa una última vez**

```bash
bundle exec rspec
```

Expected: toda la suite verde. Comparar con el número de ejemplos del baseline (Task 1.3) — debería ser baseline + ~30 nuevos.

- [ ] **Step 2: Lint global**

```bash
bundle exec rubocop
```

Expected: `no offenses detected`. Si hay offenses introducidos por este feature, correr `bundle exec rubocop -a` sobre los archivos afectados.

- [ ] **Step 3: Verificación manual del flujo**

Levantar `bin/dev`, ir a `http://localhost:3000`. Loguearse como admin. Verificar:

1. **`/web/customers`** — ver columna Saldo, identificar un cliente con deuda.
2. **`/web/customers/:id/show`** — la tabla de Ventas a Crédito muestra cobrado/pendiente correctamente y los links a la orden funcionan.
3. **`/web/customers/:id/payments/new`** — ver la tabla de órdenes pendientes con resumen en vivo. Tildar 2 órdenes, asignar montos y métodos distintos, submit.
4. **Tras submit** → redirige al cliente con flash success que dice "Cobro de $X registrado sobre N órdenes".
5. **Volver al show del cliente** → cobrado/pendiente actualizado, saldo del cliente reducido.
6. **`/web/customers/:id/payments/new`** para cliente sin credit account → empty state "Sin cuenta corriente".
7. **`/web/customers/:id/payments/new`** para cliente con todo pago → empty state "Todo al día".
8. **`/web/orders/:id/show`** de una orden con allocations → ver sección "Pagos de esta Venta" con los pagos correctos.
9. **`/web/customers/debtors`** — el cliente desaparece si todo lo pendiente quedó cubierto.

- [ ] **Step 4: Commit único del feature**

```bash
git add -A
git status  # revisar que solo están los archivos esperados
git commit -m "feat (feat_06): payment allocation to orders

- New PaymentAllocation join table (payment_id, order_id, amount)
- Drop payments.order_id; payments now represent tenders (single method)
- Payments::AllocatePayment service: groups allocations by method, creates one Payment per method group with their allocations in a transaction
- Order#outstanding_balance reads from payment_allocations
- Sales::CreateOrder.initial_payment creates Payment + Allocation
- Sales::CancelOrder destroys allocations only (payments stay alive; known limitation)
- New multi-order payment form: table with per-row checkbox, amount, method, live summary
- Empty states: no credit account, no pending orders
- orders/show and customers/show read payments via allocations
- Update WORKING_CONTEXT.md and DEVELOPMENT_GUIDE.md to reflect new payment model"
```

- [ ] **Step 5: Verificar el commit**

```bash
git log --oneline -3
git diff HEAD~1 --stat
```

Expected: el commit listado al tope con todos los archivos del feature.

---

## Notas para el ejecutor

- **Orden estricto:** migración → modelo allocation → refactor Payment/Order → servicios → controller → vista → docs. No saltear tasks.
- **Si un task falla a mitad:** dejar el trabajo sin commitear, pasar el contexto al siguiente loop. No commitear trabajo parcial.
- **Tests pre-existentes que rompen:** verificar contra la lista de archivos modificados (`spec/models/payment_spec.rb`, `spec/models/order_spec.rb`, `spec/services/sales/*`). Si rompe un test fuera de esta lista, **detenerse y avisar** — probablemente un cambio de comportamiento involuntario.
- **Stimulus controller:** si el manifest no se actualiza solo, correr `bin/rails stimulus:manifest:update`. Si el proyecto usa importmap, el controller se autoregistra al estar en `app/javascript/controllers/`.
- **No mover `Payments::RegisterPayment`** si todavía hay callers en el codebase — sólo si Step 17.3 confirma que no hay ninguno.
