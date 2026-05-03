# Partial payment on credit sales — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Permitir que en la creación de una venta a cuenta corriente el operador registre cuánto cobra al momento (0, parcial o total), persistiendo un `Payment` atado a la `Order` cuando aplique.

**Architecture:** Se agrega `Payment.order_id` opcional. `Sales::CreateOrder` recibe un `initial_payment:` opcional y crea el `Payment` dentro de su transacción ya existente. `Sales::CancelOrder` destruye los payments asociados al cancelar. La vista de venta muestra dos campos extra (monto + método) condicionales al toggle "Cuenta Corriente" mediante el Stimulus controller `order-form` ya existente.

**Tech Stack:** Rails 7.2, PostgreSQL, HAML, Stimulus, RSpec, FactoryBot, TailwindCSS.

**Spec:** [docs/superpowers/specs/2026-04-30-partial-payment-on-credit-sales-design.md](../specs/2026-04-30-partial-payment-on-credit-sales-design.md).

---

## File map

**Migración (nueva):**
- `db/migrate/<timestamp>_add_order_to_payments.rb` — agrega FK opcional a `payments`.

**Modificar:**
- `app/models/payment.rb` — agregar `belongs_to :order, optional: true` + validación condicional.
- `app/models/order.rb` — agregar `has_many :payments, dependent: :destroy`.
- `app/services/sales/create_order.rb` — agregar parámetro `initial_payment:`, validar, crear `Payment` dentro de la transacción.
- `app/services/sales/cancel_order.rb` — destruir `@order.payments` dentro de la transacción de cancelación.
- `app/controllers/web/orders_controller.rb` — pasar `initial_payment:` al servicio + helper `parse_initial_payment`.
- `app/views/web/orders/new.html.haml` — bloque condicional con dos campos.
- `app/javascript/controllers/order_form_controller.js` — nuevas targets y método `updateInitialPayment`.
- `WORKING_CONTEXT.md` — reflejar los cambios.

**Tests (modificar):**
- `spec/models/payment_spec.rb` — asociación a `Order` + validación de monto.
- `spec/services/sales/create_order_spec.rb` — contexto `with initial_payment`.
- `spec/services/sales/cancel_order_spec.rb` — destrucción de payments al cancelar.

**Tests (nuevos):**
- `spec/requests/web/orders_spec.rb` — request spec para POST `/web/orders` con/sin pago inicial.

---

## Conventions used in every task

- Siempre TDD: escribir test → ver fallar → implementar → ver pasar → commit.
- Comandos:
  - `bundle exec rspec <path>` para correr tests.
  - `bundle exec rubocop` para lint antes de cada commit (si falla, `bundle exec rubocop -a` y volver a commitear).
- Mensajes de commit en estilo del proyecto: `feat (feat_04): …`, `test (feat_04): …`, `refactor (feat_04): …`.
- Ningún `git push` automático: la última task ofrece el push.

---

## Task 1: Setup — branch nueva desde main + baseline verde

**Files:** ninguno (sólo git + run baseline).

- [ ] **Step 1: Confirmar que `main` está limpio y actualizado**

```bash
git fetch origin
git status
```

Expected: working tree clean en la rama actual (`feat_03-partial-invoices-and-sales-ui`). Si hay cambios sin commitear, detenerse y avisar al usuario.

- [ ] **Step 2: Crear branch nueva desde `origin/main`**

```bash
git checkout -b feat_04-partial-payment-on-credit-sales origin/main
```

Expected: `Switched to a new branch 'feat_04-partial-payment-on-credit-sales'`.

- [ ] **Step 3: Verificar baseline de tests**

```bash
bundle exec rspec
```

Expected: la suite pasa toda (mismo estado que `main`). Si hay fallos pre-existentes en `main`, anotarlos y NO seguir hasta hablarlo con el usuario.

- [ ] **Step 4: Verificar lint baseline**

```bash
bundle exec rubocop
```

Expected: `no offenses detected` (o el estado que tenga `main`).

---

## Task 2: Migration — agregar `order_id` a `payments`

**Files:**
- Create: `db/migrate/<timestamp>_add_order_to_payments.rb`
- Modify: `db/schema.rb` (lo regenera Rails)

- [ ] **Step 1: Generar la migración**

```bash
bundle exec rails generate migration AddOrderToPayments order:references
```

Esto crea el archivo `db/migrate/<timestamp>_add_order_to_payments.rb`.

- [ ] **Step 2: Ajustar el contenido para que sea nullable**

Reemplazar el contenido del archivo recién creado con:

```ruby
class AddOrderToPayments < ActiveRecord::Migration[7.2]
  def change
    add_reference :payments, :order, null: true, foreign_key: true, index: true
  end
end
```

Notas:
- `null: true` es lo crítico: los payments sueltos existentes deben seguir funcionando.
- Si el `rails generate` ya generó algo equivalente con `null: false`, sobreescribir con el bloque de arriba.

- [ ] **Step 3: Correr la migración**

```bash
bundle exec rails db:migrate
```

Expected: `== AddOrderToPayments: migrated`. Verifica que `db/schema.rb` se actualice con `t.bigint "order_id"` y `t.index ["order_id"]`.

- [ ] **Step 4: Correr la suite para confirmar que nada se rompió**

```bash
bundle exec rspec
```

Expected: toda la suite verde (la columna nueva no afecta a nadie aún).

- [ ] **Step 5: Commit**

```bash
git add db/migrate db/schema.rb
git commit -m "feat (feat_04): add nullable order_id to payments

Backfills nothing; existing standalone payments keep order_id NULL."
```

---

## Task 3: `Payment` model — asociación opcional + validación

**Files:**
- Modify: `app/models/payment.rb`
- Test: `spec/models/payment_spec.rb`

- [ ] **Step 1: Escribir tests fallando para la asociación y la validación**

Editar `spec/models/payment_spec.rb`. Dentro de `describe "associations"`, agregar:

```ruby
it { should belong_to(:order).optional }
```

Dentro de `describe "validations"`, después del bloque `customer_must_have_credit_account`, agregar:

```ruby
describe "amount_within_order_total" do
  let(:customer) { create(:customer, :with_credit) }
  let(:product) { create(:product, current_stock: 10, price_unit: 100) }
  let!(:stock_location) { create(:stock_location) }
  let(:credit_order) do
    Sales::CreateOrder.call(
      customer: customer,
      items: [ { product_id: product.id, quantity: 2, unit_price: 100 } ],
      order_type: "credit"
    ).record
  end

  it "is valid when amount equals order total" do
    payment = build(:payment, customer: customer, order: credit_order, amount: credit_order.total_amount)
    expect(payment).to be_valid
  end

  it "is valid when amount is below order total" do
    payment = build(:payment, customer: customer, order: credit_order, amount: credit_order.total_amount - 1)
    expect(payment).to be_valid
  end

  it "is invalid when amount exceeds order total" do
    payment = build(:payment, customer: customer, order: credit_order, amount: credit_order.total_amount + 1)
    expect(payment).not_to be_valid
    expect(payment.errors[:amount].first).to match(/no puede exceder el total de la orden/)
  end

  it "is valid when order is nil (standalone payment)" do
    payment = build(:payment, customer: customer, order: nil, amount: 999_999)
    expect(payment).to be_valid
  end
end
```

- [ ] **Step 2: Correr los tests para verificar que fallan**

```bash
bundle exec rspec spec/models/payment_spec.rb
```

Expected: los nuevos ejemplos fallan con `NoMethodError`/`AssociationNotFoundError` (la asociación todavía no existe). Los ejemplos antiguos siguen pasando.

- [ ] **Step 3: Implementar la asociación y la validación**

Editar `app/models/payment.rb`. El archivo final queda así:

```ruby
# frozen_string_literal: true

class Payment < ApplicationRecord
  # Associations
  belongs_to :customer
  belongs_to :order, optional: true

  # Constants
  PAYMENT_METHODS = %w[cash transfer check card].freeze

  # Validations
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :payment_method, presence: true, inclusion: { in: PAYMENT_METHODS }
  validates :payment_date, presence: true
  validate :customer_must_have_credit_account
  validate :amount_within_order_total, if: :order

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

  def amount_within_order_total
    return if amount.nil? || order.total_amount.nil?
    if amount > order.total_amount
      errors.add(:amount, "no puede exceder el total de la orden ($#{order.total_amount})")
    end
  end
end
```

- [ ] **Step 4: Correr los tests del modelo**

```bash
bundle exec rspec spec/models/payment_spec.rb
```

Expected: todos verdes.

- [ ] **Step 5: Correr la suite completa**

```bash
bundle exec rspec
```

Expected: toda la suite verde (el cambio no rompe nada porque la asociación es opcional).

- [ ] **Step 6: Lint**

```bash
bundle exec rubocop app/models/payment.rb spec/models/payment_spec.rb
```

Expected: `no offenses detected`. Si hay offenses simples, `bundle exec rubocop -a app/models/payment.rb spec/models/payment_spec.rb`.

- [ ] **Step 7: Commit**

```bash
git add app/models/payment.rb spec/models/payment_spec.rb
git commit -m "feat (feat_04): allow Payment to belong to an Order optionally

Adds belongs_to :order optional and amount_within_order_total
validation. Standalone payments (order_id nil) keep working unchanged."
```

---

## Task 4: `Order` model — `has_many :payments`

**Files:**
- Modify: `app/models/order.rb`
- Test: `spec/models/order_spec.rb` (si existe; si no, omitir el test específico de asociación — ya está cubierto en specs de servicio).

- [ ] **Step 1: Editar `app/models/order.rb` para agregar la asociación**

Localizar la sección de associations (al inicio del archivo). Después de `has_many :stock_movements, ...` agregar:

```ruby
  has_many :payments, dependent: :destroy
```

El bloque final de associations queda así:

```ruby
  # Associations
  belongs_to :customer, optional: true
  has_many :order_items, dependent: :destroy
  has_many :products, through: :order_items
  has_many :stock_movements, as: :reference, dependent: :nullify
  has_many :payments, dependent: :destroy
```

- [ ] **Step 2: Verificar la asociación con un test rápido en consola opcional**

```bash
bundle exec rails runner 'puts Order.reflect_on_association(:payments).macro'
```

Expected: `has_many`.

- [ ] **Step 3: Correr la suite completa para confirmar que nada se rompe**

```bash
bundle exec rspec
```

Expected: toda la suite verde.

- [ ] **Step 4: Lint**

```bash
bundle exec rubocop app/models/order.rb
```

Expected: `no offenses detected`.

- [ ] **Step 5: Commit**

```bash
git add app/models/order.rb
git commit -m "feat (feat_04): declare has_many :payments on Order

Used by Sales::CancelOrder to destroy associated payments and by
Sales::CreateOrder for the inverse association of the new initial
payment relation."
```

---

## Task 5: `Sales::CreateOrder` — aceptar `initial_payment`

**Files:**
- Modify: `app/services/sales/create_order.rb`
- Test: `spec/services/sales/create_order_spec.rb`

- [ ] **Step 1: Escribir los tests del nuevo contexto, todos esperando fallar**

Editar `spec/services/sales/create_order_spec.rb`. Antes del último `end` (cerrando `describe '.call'`), agregar este bloque completo:

```ruby
    context 'with initial_payment' do
      let(:product) { create(:product, current_stock: 50, price_unit: 100) }
      let(:base_args) do
        {
          customer: customer_with_credit,
          items: [ { product_id: product.id, quantity: 2, unit_price: 100 } ],
          order_type: 'credit'
        }
      end

      it 'creates Order and Payment atomically when amount is partial' do
        result = described_class.call(**base_args, initial_payment: { amount: 50, payment_method: 'cash' })

        expect(result.success?).to be true
        order = result.record
        expect(order.payments.count).to eq(1)
        payment = order.payments.first
        expect(payment.amount).to eq(50)
        expect(payment.payment_method).to eq('cash')
        expect(payment.customer).to eq(customer_with_credit)
        expect(payment.payment_date).to eq(order.sale_date)
      end

      it 'creates Payment when amount equals order total' do
        result = described_class.call(**base_args, initial_payment: { amount: 200, payment_method: 'transfer' })

        expect(result.success?).to be true
        expect(result.record.payments.count).to eq(1)
        expect(result.record.payments.first.amount).to eq(200)
      end

      it 'reduces customer balance by the paid amount' do
        described_class.call(**base_args, initial_payment: { amount: 50, payment_method: 'cash' })
        expect(customer_with_credit.current_balance).to eq(150) # 200 total - 50 pagado
      end

      it 'does not create Payment when amount is zero' do
        result = described_class.call(**base_args, initial_payment: { amount: 0, payment_method: 'cash' })

        expect(result.success?).to be true
        expect(result.record.payments.count).to eq(0)
      end

      it 'does not create Payment when initial_payment is nil' do
        result = described_class.call(**base_args, initial_payment: nil)

        expect(result.success?).to be true
        expect(result.record.payments.count).to eq(0)
      end

      it 'rejects initial_payment when order_type is immediate' do
        result = described_class.call(
          **base_args.merge(order_type: 'immediate', customer: customer_without_credit),
          initial_payment: { amount: 50, payment_method: 'cash' }
        )

        expect(result.success?).to be false
        expect(result.errors).to include('El cobro al momento solo aplica a ventas a cuenta corriente')
      end

      it 'rejects amount greater than total' do
        result = described_class.call(**base_args, initial_payment: { amount: 500, payment_method: 'cash' })

        expect(result.success?).to be false
        expect(result.errors).to include(/El monto cobrado no puede exceder el total de la venta/)
      end

      it 'rejects invalid payment_method' do
        result = described_class.call(**base_args, initial_payment: { amount: 50, payment_method: 'crypto' })

        expect(result.success?).to be false
        expect(result.errors).to include('Método de pago inválido')
      end

      it 'rolls back the order when Payment.create! raises' do
        allow(Payment).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(Payment.new))

        initial_orders   = Order.count
        initial_items    = OrderItem.count
        initial_payments = Payment.count
        initial_movements = StockMovement.count

        described_class.call(**base_args, initial_payment: { amount: 50, payment_method: 'cash' })

        expect(Order.count).to eq(initial_orders)
        expect(OrderItem.count).to eq(initial_items)
        expect(Payment.count).to eq(initial_payments)
        expect(StockMovement.count).to eq(initial_movements)
      end
    end
```

- [ ] **Step 2: Correr los tests del nuevo contexto y verificar que fallan**

```bash
bundle exec rspec spec/services/sales/create_order_spec.rb -e "with initial_payment"
```

Expected: todos los ejemplos del nuevo contexto fallan (el servicio aún no acepta `initial_payment`). Los demás contextos siguen verdes.

- [ ] **Step 3: Implementar el cambio en el servicio**

Reemplazar el contenido completo de `app/services/sales/create_order.rb` con esta versión:

```ruby
module Sales
  # Sales::CreateOrder
  #
  # Service para crear órdenes de venta.
  #
  # Soporta dos modos:
  # 1. LIVE (default): Venta en tiempo real con precios de BD
  # 2. FROM_PAPER: Venta cargada desde talonario físico
  #    - Permite unit_price nil (se trata como 0)
  #    - Permite total_amount = 0
  #    - Requiere paper_number para cruzar con talonario físico
  #
  # En ambos modos:
  # - Valida stock disponible
  # - Crea stock_movements de salida
  # - Actualiza current_stock de productos
  #
  # Para órdenes a crédito acepta opcionalmente initial_payment:
  #   { amount: <decimal>, payment_method: <string> }
  # cuando viene, se crea un Payment atado a la Order dentro de la
  # misma transacción.
  class CreateOrder
    Item = Struct.new(:product_id, :quantity, :unit_price, keyword_init: true)

    def self.call(customer:, items:, order_type:, channel: nil, source: "live",
                  sale_date: nil, paper_number: nil, initial_payment: nil)
      new(
        customer: customer,
        items: items,
        order_type: order_type,
        channel: channel,
        source: source,
        sale_date: sale_date,
        paper_number: paper_number,
        initial_payment: initial_payment
      ).call
    end

    def initialize(customer:, items:, order_type:, channel: nil, source: "live",
                   sale_date: nil, paper_number: nil, initial_payment: nil)
      @customer = customer
      @items = items.map { |item| item.is_a?(Item) ? item : Item.new(item) }
      @order_type = order_type
      @channel = channel
      @source = source
      @sale_date = sale_date || Date.today
      @paper_number = paper_number
      @initial_payment = normalize_initial_payment(initial_payment)
    end

    def call
      validate_params

      ActiveRecord::Base.transaction do
        create_order
        create_order_items
        create_stock_movements
        create_initial_payment if @initial_payment

        Result.new(success?: true, record: @order, errors: [])
      end
    rescue ValidationError => e
      Result.new(success?: false, record: nil, errors: [ e.message ])
    rescue StandardError => e
      Rails.logger.error("Error in Sales::CreateOrder: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      Result.new(success?: false, record: nil, errors: [ "Error creating order" ])
    end

    private

    class ValidationError < StandardError; end

    # Si amount viene 0 o nil, anula initial_payment para no crear Payment.
    def normalize_initial_payment(initial_payment)
      return nil if initial_payment.nil?
      amount = initial_payment[:amount].to_f
      return nil if amount <= 0

      {
        amount: amount,
        payment_method: initial_payment[:payment_method]
      }
    end

    def validate_params
      unless %w[immediate credit].include?(@order_type)
        raise ValidationError, "Invalid order type"
      end

      raise ValidationError, "Customer is required" if @customer.nil?

      if @order_type == "credit" && !@customer.has_credit_account?
        raise ValidationError, "Customer does not have credit account enabled"
      end

      raise ValidationError, "At least one product is required" if @items.blank?

      @items.each do |item|
        raise ValidationError, "Product ID is required" unless item.product_id
        raise ValidationError, "Quantity must be greater than zero" unless item.quantity.to_i > 0
      end

      unless @source == "from_paper"
        @items.each do |item|
          product = Product.find(item.product_id)
          if product.current_stock < item.quantity
            raise ValidationError, "Insufficient stock for #{product.name}. Available: #{product.current_stock}"
          end
        end
      end

      validate_initial_payment if @initial_payment
    end

    def validate_initial_payment
      if @order_type != "credit"
        raise ValidationError, "El cobro al momento solo aplica a ventas a cuenta corriente"
      end

      total = calculate_total
      if @initial_payment[:amount] > total
        raise ValidationError, "El monto cobrado no puede exceder el total de la venta ($#{total})"
      end

      unless Payment::PAYMENT_METHODS.include?(@initial_payment[:payment_method])
        raise ValidationError, "Método de pago inválido"
      end
    end

    def create_order
      @order = Order.create!(
        customer: @customer,
        order_type: @order_type,
        channel: @channel,
        source: @source,
        sale_date: @sale_date,
        paper_number: @paper_number,
        status: "confirmed",
        total_amount: calculate_total
      )
    end

    def calculate_total
      @items.sum do |item|
        product = Product.find(item.product_id)
        unit_price = item.unit_price || product.price_unit || 0
        item.quantity * unit_price
      end
    end

    def create_order_items
      @items.each do |item|
        product = Product.find(item.product_id)
        final_price = item.unit_price || product.price_unit || 0

        OrderItem.create!(
          order: @order,
          product: product,
          quantity: item.quantity,
          unit_price: final_price
        )
      end
    end

    def create_stock_movements
      stock_location = StockLocation.first!

      @order.order_items.each do |order_item|
        result = Inventory::AdjustStock.call(
          product: order_item.product,
          stock_location: stock_location,
          movement_type: "sale",
          quantity: -order_item.quantity,
          reference: @order,
          note: "Sale ##{@order.id}",
          allow_negative: @source == "from_paper"
        )

        raise ValidationError, result.errors.join(", ") if result.failure?
      end
    end

    def create_initial_payment
      Payment.create!(
        customer: @customer,
        order: @order,
        amount: @initial_payment[:amount],
        payment_method: @initial_payment[:payment_method],
        payment_date: @sale_date
      )
    end
  end
end
```

Notas:
- `normalize_initial_payment` colapsa `amount: 0` y `nil` al mismo "sin pago". Eso simplifica el flujo del controller (puede pasar `0` sin que se cree un payment vacío).
- Las nuevas validaciones (`validate_initial_payment`) sólo corren si `@initial_payment` está presente, así que no afectan a las llamadas viejas.
- `create_initial_payment` corre **después** de `create_stock_movements` para que cualquier rollback temprano no requiera limpiar payments huérfanos.

- [ ] **Step 4: Correr los tests del nuevo contexto**

```bash
bundle exec rspec spec/services/sales/create_order_spec.rb -e "with initial_payment"
```

Expected: todos verdes.

- [ ] **Step 5: Correr la suite completa para confirmar no-regresión**

```bash
bundle exec rspec
```

Expected: toda la suite verde. Si algún spec previo de `create_order` falla, hay un cambio de comportamiento involuntario — revisar antes de seguir.

- [ ] **Step 6: Lint**

```bash
bundle exec rubocop app/services/sales/create_order.rb spec/services/sales/create_order_spec.rb
```

Expected: `no offenses detected`. Si falla, `bundle exec rubocop -a` y volver a correr.

- [ ] **Step 7: Commit**

```bash
git add app/services/sales/create_order.rb spec/services/sales/create_order_spec.rb
git commit -m "feat (feat_04): Sales::CreateOrder accepts optional initial_payment

When initial_payment: { amount:, payment_method: } is provided on a
credit order, creates a Payment tied to the new Order in the same
transaction. Amount must be 0 < amount <= total. Existing call sites
with no initial_payment behave identically."
```

---

## Task 6: `Sales::CancelOrder` — destruir payments asociados

**Files:**
- Modify: `app/services/sales/cancel_order.rb`
- Test: `spec/services/sales/cancel_order_spec.rb`

- [ ] **Step 1: Escribir el test fallando**

Editar `spec/services/sales/cancel_order_spec.rb`. Dentro del bloque `context 'with credit order' do … end`, agregar el siguiente ejemplo (después del existente `'reduces customer balance when cancelled'`):

```ruby
      it 'destroys associated payments when cancelled' do
        order_with_payment_result = Sales::CreateOrder.call(
          customer: customer,
          items: [ { product_id: product.id, quantity: 5, unit_price: 100 } ],
          order_type: 'credit',
          initial_payment: { amount: 200, payment_method: 'cash' }
        )
        order_with_payment = order_with_payment_result.record
        expect(order_with_payment.payments.count).to eq(1)

        described_class.call(order: order_with_payment)

        expect(order_with_payment.reload.payments.count).to eq(0)
        expect(Payment.where(order_id: order_with_payment.id)).to be_empty
      end

      it 'restores customer balance fully even when an initial payment existed' do
        result = Sales::CreateOrder.call(
          customer: customer,
          items: [ { product_id: product.id, quantity: 5, unit_price: 100 } ],
          order_type: 'credit',
          initial_payment: { amount: 200, payment_method: 'cash' }
        )
        order_with_payment = result.record
        # 500 (credit) - 200 (payment) = 300 antes de cancelar
        expect(customer.current_balance).to eq(300)

        described_class.call(order: order_with_payment)

        # Cancelada: 0 credit no canceladas - 0 payments = 0
        expect(customer.reload.current_balance).to eq(0)
      end
```

- [ ] **Step 2: Correr el test y verificar fallo**

```bash
bundle exec rspec spec/services/sales/cancel_order_spec.rb -e "destroys associated payments"
bundle exec rspec spec/services/sales/cancel_order_spec.rb -e "restores customer balance fully"
```

Expected: ambos fallan — el primero porque el Payment sigue existiendo después de cancelar; el segundo porque `current_balance` queda en `-200` (la deuda se quitó pero el pago sigue).

- [ ] **Step 3: Implementar la destrucción de payments en el servicio**

Editar `app/services/sales/cancel_order.rb`. El archivo final queda así:

```ruby
module Sales
  class CancelOrder
    def self.call(order:, reason: nil)
      new(order: order, reason: reason).call
    end

    def initialize(order:, reason: nil)
      @order = order
      @reason = reason
    end

    def call
      validate_params

      ActiveRecord::Base.transaction do
        cancel_order
        reverse_stock_movements
        destroy_associated_payments

        Result.new(success?: true, record: @order, errors: [])
      end
    rescue ValidationError => e
      Result.new(success?: false, record: nil, errors: [ e.message ])
    rescue StandardError => e
      Rails.logger.error("Error in Sales::CancelOrder: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      Result.new(success?: false, record: nil, errors: [ "Error cancelling order" ])
    end

    private

    class ValidationError < StandardError; end

    def validate_params
      raise ValidationError, "Order is already cancelled" if @order.cancelled_status?
    end

    def cancel_order
      @order.update!(status: "cancelled")
    end

    def reverse_stock_movements
      stock_location = StockLocation.first!

      @order.order_items.each do |item|
        result = Inventory::AdjustStock.call(
          product: item.product,
          stock_location: stock_location,
          movement_type: "adjustment",
          quantity: item.quantity,
          reference: @order,
          note: @reason || "Order ##{@order.id} cancellation"
        )

        raise ValidationError, result.errors.join(", ") if result.failure?
      end
    end

    def destroy_associated_payments
      @order.payments.destroy_all
    end
  end
end
```

Notas:
- `destroy_associated_payments` corre dentro del mismo `transaction`, por lo que un fallo en el reverse_stock_movements no destruye payments — y un fallo aquí mismo (poco probable, pero posible) revierte la cancelación entera.
- Si `@order.payments` está vacío, `destroy_all` es un no-op barato.

- [ ] **Step 4: Correr los nuevos tests**

```bash
bundle exec rspec spec/services/sales/cancel_order_spec.rb
```

Expected: toda la suite del file verde.

- [ ] **Step 5: Correr la suite completa**

```bash
bundle exec rspec
```

Expected: toda la suite verde.

- [ ] **Step 6: Lint**

```bash
bundle exec rubocop app/services/sales/cancel_order.rb spec/services/sales/cancel_order_spec.rb
```

Expected: `no offenses detected`.

- [ ] **Step 7: Commit**

```bash
git add app/services/sales/cancel_order.rb spec/services/sales/cancel_order_spec.rb
git commit -m "feat (feat_04): Sales::CancelOrder destroys associated payments

Symmetric with how stock is restocked: the cancellation undoes both the
sale and any initial payment recorded against that sale, keeping the
customer's current_balance coherent."
```

---

## Task 7: `Web::OrdersController#create` — pasar `initial_payment`

**Files:**
- Modify: `app/controllers/web/orders_controller.rb`
- Create: `spec/requests/web/orders_spec.rb`

- [ ] **Step 1: Crear el request spec con dos tests fallando**

Crear el archivo `spec/requests/web/orders_spec.rb` con este contenido:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Web::Orders", type: :request do
  let!(:stock_location) { create(:stock_location) }
  let(:vendedor) { create(:user, role: "vendedor") }
  let(:customer_with_credit) { create(:customer, :with_credit) }
  let(:product) { create(:product, current_stock: 50, price_unit: 100) }

  before { sign_in vendedor }

  describe "POST /web/orders" do
    let(:base_params) do
      {
        order: {
          customer_id: customer_with_credit.id,
          order_type: "credit",
          channel: "counter"
        },
        purchase_items: [
          { product_id: product.id, quantity: "2", unit_price: "100" }
        ],
        sale_date: Date.today.iso8601,
        paper_number: "0099"
      }
    end

    context "with initial_payment_amount on a credit order" do
      it "creates Order and a Payment tied to it" do
        expect {
          post "/web/orders", params: base_params.merge(
            initial_payment_amount: "50",
            initial_payment_method: "cash"
          )
        }.to change(Order, :count).by(1).and change(Payment, :count).by(1)

        order = Order.order(:created_at).last
        payment = Payment.order(:created_at).last
        expect(payment.order_id).to eq(order.id)
        expect(payment.amount).to eq(50)
        expect(payment.payment_method).to eq("cash")
      end
    end

    context "with initial_payment_amount on an immediate order" do
      it "ignores the amount and creates only the Order" do
        retail_customer = create(:customer, has_credit_account: false)

        expect {
          post "/web/orders", params: base_params.deep_merge(
            order: { customer_id: retail_customer.id, order_type: "immediate" }
          ).merge(
            initial_payment_amount: "50",
            initial_payment_method: "cash"
          )
        }.to change(Order, :count).by(1).and change(Payment, :count).by(0)
      end
    end

    context "with no initial_payment_amount on a credit order" do
      it "creates the Order with no Payment" do
        expect {
          post "/web/orders", params: base_params
        }.to change(Order, :count).by(1).and change(Payment, :count).by(0)
      end
    end

    context "with initial_payment_amount = 0 on a credit order" do
      it "creates the Order with no Payment" do
        expect {
          post "/web/orders", params: base_params.merge(
            initial_payment_amount: "0",
            initial_payment_method: "cash"
          )
        }.to change(Order, :count).by(1).and change(Payment, :count).by(0)
      end
    end
  end
end
```

Notas para quien implemente:
- Si `sign_in` no está disponible, agregar `include Devise::Test::IntegrationHelpers` dentro del bloque (suele estar configurado globalmente en `rails_helper.rb`; verificar antes de duplicar).
- Si no existe factory `:user` con `role`, revisar `spec/factories/users.rb` y ajustar (el rol `vendedor` es necesario para pasar `OrderPolicy#create?`).

- [ ] **Step 2: Correr el spec y verificar fallos**

```bash
bundle exec rspec spec/requests/web/orders_spec.rb
```

Expected: el primer ejemplo falla (no se crea el Payment porque el controller aún no parsea `initial_payment_amount`); los demás probablemente pasen porque ya hoy se ignora ese parámetro.

- [ ] **Step 3: Modificar el controller**

Editar `app/controllers/web/orders_controller.rb`. Cambios:

**3a.** Reemplazar el método `create` por:

```ruby
    def create
      authorize Order, :create?
      result = Sales::CreateOrder.call(
        customer: find_or_create_customer,
        items: parse_items,
        order_type: params.dig(:order, :order_type) || "immediate",
        channel: params.dig(:order, :channel),
        source: params[:source] || "live",
        sale_date: params[:sale_date],
        paper_number: params[:paper_number],
        initial_payment: parse_initial_payment
      )

      if result.success?
        redirect_to web_orders_path, notice: "Venta registrada exitosamente"
      else
        flash.now[:alert] = result.errors.join(", ")
        @order = Order.new
        render :new, status: :unprocessable_entity
      end
    end
```

**3b.** En la sección `private`, después de `parse_items`, agregar el helper:

```ruby
    def parse_initial_payment
      return nil unless params.dig(:order, :order_type) == "credit"
      return nil if params[:initial_payment_amount].blank?

      amount = params[:initial_payment_amount].to_f
      return nil if amount <= 0

      {
        amount: amount,
        payment_method: params[:initial_payment_method].presence || "cash"
      }
    end
```

- [ ] **Step 4: Correr el request spec**

```bash
bundle exec rspec spec/requests/web/orders_spec.rb
```

Expected: los cuatro ejemplos verdes.

- [ ] **Step 5: Correr la suite completa**

```bash
bundle exec rspec
```

Expected: todo verde.

- [ ] **Step 6: Lint**

```bash
bundle exec rubocop app/controllers/web/orders_controller.rb spec/requests/web/orders_spec.rb
```

Expected: `no offenses detected`.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/web/orders_controller.rb spec/requests/web/orders_spec.rb
git commit -m "feat (feat_04): wire initial_payment params through OrdersController

Adds parse_initial_payment which turns the new form fields into the
service hash. Defensive: only forwards when order_type is credit and
amount > 0."
```

---

## Task 8: HAML view — campos condicionales en `new.html.haml`

**Files:**
- Modify: `app/views/web/orders/new.html.haml`

- [ ] **Step 1: Localizar el bloque a modificar**

Abrir `app/views/web/orders/new.html.haml`. Encontrar el final del Card 1 *Información del Cliente*, justo después del bloque del selector de cliente y ANTES del bloque del canal de venta (`Canal de Venta`). Es la línea que dice:

```haml
          %p.text-xs.text-gray-500.mt-1 Para ventas a crédito, selecciona un cliente con cuenta corriente
```

(actualmente alrededor de [new.html.haml:78](app/views/web/orders/new.html.haml#L78))

- [ ] **Step 2: Insertar el bloque condicional de cobro al momento entre cliente y canal**

Inmediatamente después del párrafo `%p.text-xs.text-gray-500.mt-1 Para ventas a crédito, selecciona un cliente con cuenta corriente`, agregar este bloque (manteniendo la indentación de los hermanos del `space-y-4`):

```haml
          -# Cobro al momento (visible solo en cuenta corriente)
          %div{ data: { order_form_target: "creditPaymentSection" }, class: "space-y-3 hidden border-t border-gray-200 pt-4" }
            %h4.text-sm.font-semibold.text-gray-900.mb-3 Cobro al Momento

            %div
              = label_tag :initial_payment_amount, "Monto que paga ahora", class: "block text-sm font-medium text-gray-700 mb-2"
              = number_field_tag :initial_payment_amount, 0,
                  step: "0.01", min: "0",
                  data: { order_form_target: "initialPaymentInput", action: "input->order-form#updateInitialPayment" },
                  class: "w-full px-4 py-3 border border-gray-300 rounded-xl focus:ring-2 focus:ring-gray-700 focus:border-transparent transition-all"
              %p.text-xs.text-gray-500.mt-1 Dejá en 0 si el cliente no paga nada al momento
              %p.text-xs.text-red-600.mt-1.hidden{ data: { order_form_target: "initialPaymentWarning" } } El monto no puede superar el total

            %div
              = label_tag :initial_payment_method, "Método de pago", class: "block text-sm font-medium text-gray-700 mb-2"
              = select_tag :initial_payment_method,
                  options_for_select([["💵 Efectivo", "cash"], ["🏦 Transferencia", "transfer"], ["📄 Cheque", "check"], ["💳 Tarjeta", "card"]], "cash"),
                  class: "w-full px-4 py-3 border border-gray-300 rounded-xl focus:ring-2 focus:ring-gray-700 focus:border-transparent transition-all"
```

Notas:
- El bloque empieza con `class: "... hidden ..."` para que el estado inicial sea oculto. El Stimulus controller lo va a destapar cuando el toggle esté en credit.
- El input de monto trae `data-order-form-target="initialPaymentInput"` y `data-action="input->order-form#updateInitialPayment"` — lo necesita Task 9.
- `initialPaymentWarning` es el target para mostrar el aviso "no puede superar el total" cuando aplique.

- [ ] **Step 3: Confirmar que la vista renderiza sin errores**

Sin Stimulus aún, el bloque queda escondido por `hidden` y no debería tirar errores en `rspec` ni en `rails s`. Para una verificación rápida (opcional pero recomendable):

```bash
bundle exec rails runner 'puts ActionController::Base.helpers.number_field_tag(:initial_payment_amount, 0).present?'
```

Expected: `true` (es solo para confirmar que el helper existe; nada más).

- [ ] **Step 4: Correr la suite completa**

```bash
bundle exec rspec
```

Expected: todo verde — `bundle exec rspec` no carga el browser pero sí render parcial en feature/system specs si los hubiera; igual conviene correr.

- [ ] **Step 5: Lint (HAML lint si está configurado, sino skip)**

```bash
bundle exec rubocop app/views/web/orders/new.html.haml 2>/dev/null || echo "rubocop no analiza HAML, skip"
```

Expected: o pasa o el `echo` confirma que se saltea (rubocop por default no lintea HAML).

- [ ] **Step 6: Commit**

```bash
git add app/views/web/orders/new.html.haml
git commit -m "feat (feat_04): add conditional initial-payment fields to new sale form

Adds 'Monto que paga ahora' and 'Método de pago' inputs inside Card 1.
Block starts hidden; Stimulus controller will toggle visibility based
on the order_type radio."
```

---

## Task 9: Stimulus — extender `order_form_controller.js`

**Files:**
- Modify: `app/javascript/controllers/order_form_controller.js`

- [ ] **Step 1: Agregar las nuevas targets al array**

En la primera línea de la clase (alrededor de [order_form_controller.js:4](app/javascript/controllers/order_form_controller.js#L4)), reemplazar:

```js
  static targets = ["items", "total", "itemCount", "totalQuantity", "submitButton", "orderTypeInfo", "creditRadio", "immediateRadio"]
```

por:

```js
  static targets = ["items", "total", "itemCount", "totalQuantity", "submitButton", "orderTypeInfo", "creditRadio", "immediateRadio", "creditPaymentSection", "initialPaymentInput", "initialPaymentWarning"]
```

- [ ] **Step 2: Extender `updateOrderType` para mostrar/ocultar la sección de cobro**

Localizar el método `updateOrderType(event)` (alrededor de [order_form_controller.js:135](app/javascript/controllers/order_form_controller.js#L135)). Reemplazarlo por:

```js
  updateOrderType(event) {
    const orderType = event.target.value

    if (this.hasOrderTypeInfoTarget) {
      const infoTarget = this.orderTypeInfoTarget

      if (orderType === "immediate") {
        infoTarget.innerHTML = `
          <span>💵</span>
          <span class="text-gray-600">Contado - Pago inmediato</span>
        `
      } else {
        infoTarget.innerHTML = `
          <span>📋</span>
          <span class="text-gray-600">Cuenta Corriente - A crédito</span>
        `
      }
    }

    this.toggleCreditPaymentSection(orderType)
  }

  toggleCreditPaymentSection(orderType) {
    if (!this.hasCreditPaymentSectionTarget) return

    if (orderType === "credit") {
      this.creditPaymentSectionTarget.classList.remove("hidden")
    } else {
      this.creditPaymentSectionTarget.classList.add("hidden")
      if (this.hasInitialPaymentInputTarget) {
        this.initialPaymentInputTarget.value = 0
      }
      if (this.hasInitialPaymentWarningTarget) {
        this.initialPaymentWarningTarget.classList.add("hidden")
      }
    }
    this.updateSummary()
  }
```

Notas:
- Cuando se vuelve a `immediate`, el monto se resetea a `0` para que el form submit no envíe un valor residual (defensa en profundidad: el controller del backend igual lo descarta).

- [ ] **Step 3: Agregar el método `updateInitialPayment`**

Justo después de `toggleCreditPaymentSection`, agregar:

```js
  updateInitialPayment(event) {
    const value = parseFloat(event.currentTarget.value) || 0
    const total = this.calculateTotal()

    if (this.hasInitialPaymentWarningTarget) {
      if (value > total) {
        this.initialPaymentWarningTarget.classList.remove("hidden")
      } else {
        this.initialPaymentWarningTarget.classList.add("hidden")
      }
    }

    if (this.hasSubmitButtonTarget) {
      const overTotal = value > total
      this.submitButtonTarget.disabled = overTotal || this.items.length === 0
      if (overTotal || this.items.length === 0) {
        this.submitButtonTarget.classList.add("opacity-50", "cursor-not-allowed")
      } else {
        this.submitButtonTarget.classList.remove("opacity-50", "cursor-not-allowed")
      }
    }

    this.updateSummary()
  }

  calculateTotal() {
    return this.items.reduce((sum, item) => sum + (item.price_unit * item.quantity), 0)
  }
```

Notas:
- `calculateTotal()` se factoriza para reutilizar dentro de `updateSummary()` y `updateInitialPayment()`. Si tu lectura de `updateSummary` muestra que ya hace `this.items.reduce(...)` inline, refactorizar para que use `calculateTotal()` en lugar de duplicar la fórmula. (Ver paso 4.)

- [ ] **Step 4: Refactorizar `updateSummary` para reutilizar `calculateTotal()` y mostrar líneas de cobro**

Reemplazar el método `updateSummary()` por:

```js
  updateSummary() {
    const total = this.calculateTotal()
    const itemCount = this.items.length
    const totalQuantity = this.items.reduce((sum, item) => sum + item.quantity, 0)

    if (this.hasTotalTarget) {
      this.totalTarget.textContent = `$${this.formatCurrency(total)}`
    }

    if (this.hasItemCountTarget) {
      this.itemCountTarget.textContent = `${itemCount} producto${itemCount !== 1 ? 's' : ''}`
    }

    if (this.hasTotalQuantityTarget) {
      this.totalQuantityTarget.textContent = `${totalQuantity} unidad${totalQuantity !== 1 ? 'es' : ''}`
    }

    if (this.hasSubmitButtonTarget) {
      const initialPayment = this.hasInitialPaymentInputTarget ? (parseFloat(this.initialPaymentInputTarget.value) || 0) : 0
      const overTotal = initialPayment > total
      this.submitButtonTarget.disabled = this.items.length === 0 || overTotal
      if (this.items.length === 0 || overTotal) {
        this.submitButtonTarget.classList.add('opacity-50', 'cursor-not-allowed')
      } else {
        this.submitButtonTarget.classList.remove('opacity-50', 'cursor-not-allowed')
      }
    }
  }
```

- [ ] **Step 5: Verificación manual en navegador**

Levantar el server:

```bash
bin/dev
```

(o `bundle exec rails s` si el proyecto no usa `bin/dev`).

Abrir `http://localhost:3000/web/orders/new` en el browser. Loguearse con un usuario `vendedor` o `admin` (de seeds). Casos a verificar:

1. **Toggle Contado (default):** la sección "Cobro al Momento" no es visible.
2. **Toggle Cuenta Corriente con cliente con cuenta:** la sección aparece con el monto inicial en `0` y método "Efectivo".
3. **Volver a Contado:** la sección desaparece y el monto vuelve a `0`.
4. **Cargar productos por $200, elegir cuenta corriente, escribir `50`:** el botón Submit queda habilitado, no aparece warning.
5. **Cargar productos por $200, elegir cuenta corriente, escribir `300`:** aparece el warning rojo "El monto no puede superar el total" y el Submit se deshabilita.
6. **Bajar a `200` exactos:** el Submit se rehabilita.
7. **Submit con `50` cobrado:** redirect al index, en consola de Rails se ve `Order` y `Payment` creados con `order_id`.

Si alguno falla, depurar antes de seguir.

- [ ] **Step 6: Correr la suite completa**

```bash
bundle exec rspec
```

Expected: todo verde.

- [ ] **Step 7: Commit**

```bash
git add app/javascript/controllers/order_form_controller.js
git commit -m "feat (feat_04): order-form Stimulus shows credit payment fields

New targets creditPaymentSection, initialPaymentInput, initialPayment
Warning. Toggling order_type to credit reveals the section; switching
back hides it and resets the amount. Submit is disabled if amount
exceeds total."
```

---

## Task 10: Documentación — `WORKING_CONTEXT.md`

**Files:**
- Modify: `WORKING_CONTEXT.md`

- [ ] **Step 1: Editar la sección "Customer account payments (`Payment` model)"**

Encontrar la sección actual:

```markdown
* **`Payments::RegisterPayment`** creates a **`Payment`** tied only to **`customer`** (no `order_id`); **`Payment`** validates **`has_credit_account`** on the customer.
* **No `web` routes** expose registering these payments (seeds/specs can call the service).
```

Reemplazarla por:

```markdown
* **`Payments::RegisterPayment`** creates a **`Payment`** tied only to **`customer`** (no `order_id`); **`Payment`** validates **`has_credit_account`** on the customer.
* **`Sales::CreateOrder`** acepta `initial_payment: { amount:, payment_method: }` opcional para órdenes `credit`. Cuando viene, crea un **`Payment`** con `order_id` apuntando a la orden, dentro de la misma transacción.
* **`Sales::CancelOrder`** destruye los **`Payment`** asociados a la orden (`@order.payments.destroy_all`) dentro de su transacción.
* **`Web::Customers::PaymentsController`** registra pagos sueltos al cliente (`order_id: nil`).
```

- [ ] **Step 2: Editar la sección "Key constraints" — actualizar la nota sobre allocation**

Encontrar la línea:

```markdown
* **Customer `Payment` records are not allocated to specific orders** in the schema; **`Customer#current_balance`** is derived from credit **`Order`** totals minus **`payments`**.
```

Reemplazarla por:

```markdown
* **Los `Payment` pueden estar atados a una `Order` (cobros iniciales de venta) o ser sueltos (`order_id: nil`, abonos de cuenta corriente)**; **`Customer#current_balance`** se sigue derivando de credit **`Order`** totals minus **`payments`** (ambos casos cuentan).
```

- [ ] **Step 3: Verificar el archivo final**

```bash
git diff WORKING_CONTEXT.md
```

Expected: solo las dos sustituciones de arriba; sin otros cambios.

- [ ] **Step 4: Commit**

```bash
git add WORKING_CONTEXT.md
git commit -m "docs (feat_04): reflect partial payment on credit sales in WORKING_CONTEXT"
```

---

## Task 11: Verificación final + ofrecer push

**Files:** ninguno.

- [ ] **Step 1: Suite completa una última vez**

```bash
bundle exec rspec
```

Expected: todo verde.

- [ ] **Step 2: Lint global**

```bash
bundle exec rubocop
```

Expected: `no offenses detected` (o el mismo estado que `main`). Si aparece offenses introducidas en este feature, `bundle exec rubocop -a` y commitear con `style (feat_04): rubocop autofix`.

- [ ] **Step 3: Verificación manual del flujo completo**

Levantar `bin/dev`, ir a `/web/orders/new` y reproducir el escenario principal:

1. Login como `vendedor`.
2. Cliente con cuenta corriente seleccionado.
3. Toggle "Cuenta Corriente" → la sección aparece.
4. Cargar 2 productos × $100 → total $200.
5. Escribir monto: $50, método: Transferencia.
6. Submit → redirect al index con flash "Venta registrada exitosamente".
7. En `rails console`: `Order.last.payments` → 1 payment, `amount: 50.0`, `payment_method: "transfer"`, `order_id` apuntando a la order.
8. `Order.last.customer.current_balance` → 150.
9. Cancelar la orden desde el index (`POST /web/orders/:id/cancel`):
   - `Order.last.status` → `cancelled`.
   - `Order.last.payments` → vacío.
   - `Customer.last.current_balance` → 0.

- [ ] **Step 4: Resumen al usuario y oferta de push**

Avisar al usuario:
- Todas las tasks completadas.
- Suite verde, rubocop limpio.
- Verificación manual OK.
- Branch `feat_04-partial-payment-on-credit-sales` lista para `git push -u origin feat_04-partial-payment-on-credit-sales` y abrir PR.

NO ejecutar el `git push` sin confirmación explícita del usuario.

---

## Notas para el ejecutor

- **Orden estricto:** las tasks tienen dependencias secuenciales (modelo → servicio → controller → vista → JS). No pivotear el orden sin razón fuerte.
- **Si una task falla a mitad:** dejar el commit pendiente, pasar el contexto al siguiente loop. No commitear mitad-de-task.
- **Tests pre-existentes que rompen:** detenerse y avisar — probablemente sea un cambio de comportamiento involuntario que requiere revisión.
- **Si `sign_in` no resuelve en el request spec (Task 7):** verificar `spec/rails_helper.rb` por `Devise::Test::IntegrationHelpers`. Si falta, agregar `config.include Devise::Test::IntegrationHelpers, type: :request` y volver a correr.
- **Si la factory `:user` no soporta `role`:** mirar `spec/factories/users.rb` y ajustar la creación del vendedor (puede ser `create(:user, role: "vendedor")` o un trait).
