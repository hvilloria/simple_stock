# Customer Debt Visibility — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dar al operador visibilidad completa sobre las deudas pendientes de clientes con cuenta corriente: saldo en el index, órdenes clickeables con detalle de cobrado/pendiente en el show, links de cliente rotos reparados en `orders/show`, y una página dedicada "Cuentas por Cobrar" con todos los deudores ordenados por monto.

**Architecture:** Se agregan métodos calculados a `Order` (`outstanding_balance`) y `Customer` (`last_payment_date`, `days_without_paying`) sin migraciones. Se corrige un bug en `Payment#amount_within_order_total` que permitía sobrepagar órdenes parcialmente pagadas. Se añade un scope `Customer.with_outstanding_balance` usando subqueries correlacionadas. La UI se extiende en cascada: sidebar → customers/index → customers/show → orders/show → nueva vista debtors → dashboard.

**Tech Stack:** Rails 7.2, PostgreSQL, HAML, TailwindCSS, RSpec, FactoryBot, Pundit.

> **Nota sobre commits:** Este proyecto usa 1 commit por feature completo. NO hay pasos de commit individuales en este plan. El desarrollador hace `git add -A && git commit` una sola vez al final, en el Task 13, después de verificar que todo funciona.

**Spec:** [docs/superpowers/specs/2026-05-06-customer-debt-visibility-design.md](../specs/2026-05-06-customer-debt-visibility-design.md)

---

## File map

**Modificar:**
- `app/models/order.rb` — agregar `outstanding_balance`
- `app/models/payment.rb` — fix `amount_within_order_total`
- `app/models/customer.rb` — agregar scope + helpers de fecha
- `app/policies/customer_policy.rb` — agregar `debtors?`
- `app/controllers/web/customers_controller.rb` — agregar acción `debtors` + `includes` en `show`
- `config/routes.rb` — agregar `collection { get :debtors }`
- `app/views/layouts/web/_sidebar.html.haml` — extender Ventas group; convertir Clientes a group
- `app/views/web/customers/index.html.haml` — columna Saldo
- `app/views/web/customers/show.html.haml` — filas clickeables, cols Cobrado/Pendiente
- `app/views/web/orders/show.html.haml` — fix links rotos + sección pagos de la venta
- `app/views/web/dashboard/index.html.haml` — link en métrica receivables
- `spec/models/order_spec.rb` — nuevos ejemplos para `outstanding_balance`
- `spec/models/payment_spec.rb` — fix test existente + nuevos ejemplos
- `spec/models/customer_spec.rb` — nuevos ejemplos para scope y helpers (crear si no existe)
- `spec/requests/web/customers_spec.rb` — nuevos ejemplos para `GET /web/customers/debtors` (crear si no existe)
- `WORKING_CONTEXT.md` — reflejar nuevos métodos y página debtors

**Crear:**
- `app/views/web/customers/debtors.html.haml`

---

## Conventions used in every task

- TDD: escribir test → ver fallar → implementar → ver pasar.
- `bundle exec rspec <path>` para correr tests.
- `bundle exec rubocop <files>` para lint. Si falla, `bundle exec rubocop -a <files>`.
- Los tests de modelo usan `build` / `create` con FactoryBot; los request specs usan `sign_in`.
- Estilo de mensajes flash: español neutro.

---

## Task 1: Setup — branch nueva desde main + baseline verde

**Files:** ninguno (solo git).

- [ ] **Step 1: Verificar que la rama actual está limpia**

```bash
git status
```

Expected: `nothing to commit, working tree clean`. Si hay cambios sin commitear, detener y resolverlos primero. Nota: el spec `2026-05-06-customer-debt-visibility-design.md` fue creado pero no commiteado — es esperado, aparecerá como `Untracked files`.

- [ ] **Step 2: Crear branch nueva desde `origin/main`**

```bash
git stash  # si el spec sin commitear interfiere, guardarlo temporalmente
git checkout -b feat_05-customer-debt-visibility origin/main
git stash pop  # restaurar el spec
```

Expected: `Switched to a new branch 'feat_05-customer-debt-visibility'`.

- [ ] **Step 3: Verificar baseline de tests**

```bash
bundle exec rspec
```

Expected: suite completa verde. Si hay fallos preexistentes, anotar y NO continuar sin consultar al usuario.

- [ ] **Step 4: Verificar lint baseline**

```bash
bundle exec rubocop
```

Expected: `no offenses detected` (o el estado que tenga `main`).

---

## Task 2: `Order#outstanding_balance` — nuevo método + tests

**Files:**
- Modify: `app/models/order.rb`
- Test: `spec/models/order_spec.rb`

- [ ] **Step 1: Escribir tests fallando**

Abrir `spec/models/order_spec.rb`. Al final del archivo, antes del último `end`, agregar:

```ruby
  describe '#outstanding_balance' do
    let!(:stock_location) { create(:stock_location) }
    let(:customer) { create(:customer, :with_credit) }
    let(:product) { create(:product, current_stock: 20, price_unit: 100) }

    context 'when order is immediate' do
      let(:order) do
        Sales::CreateOrder.call(
          customer: Customer.mostrador,
          items: [{ product_id: product.id, quantity: 1, unit_price: 100 }],
          order_type: 'immediate'
        ).record
      end

      it 'returns 0 regardless of payments' do
        expect(order.outstanding_balance).to eq(0)
      end
    end

    context 'when order is credit with no linked payments' do
      let(:order) do
        Sales::CreateOrder.call(
          customer: customer,
          items: [{ product_id: product.id, quantity: 2, unit_price: 100 }],
          order_type: 'credit'
        ).record
      end

      it 'returns the full total_amount' do
        expect(order.outstanding_balance).to eq(200)
      end
    end

    context 'when order has a partial linked payment' do
      let(:order) do
        Sales::CreateOrder.call(
          customer: customer,
          items: [{ product_id: product.id, quantity: 2, unit_price: 100 }],
          order_type: 'credit',
          initial_payment: { amount: 50, payment_method: 'cash' }
        ).record
      end

      it 'returns total minus paid amount' do
        expect(order.outstanding_balance).to eq(150)
      end
    end

    context 'when order is fully paid' do
      let(:order) do
        Sales::CreateOrder.call(
          customer: customer,
          items: [{ product_id: product.id, quantity: 2, unit_price: 100 }],
          order_type: 'credit',
          initial_payment: { amount: 200, payment_method: 'cash' }
        ).record
      end

      it 'returns 0' do
        expect(order.outstanding_balance).to eq(0)
      end
    end
  end
```

- [ ] **Step 2: Correr los tests para verificar que fallan**

```bash
bundle exec rspec spec/models/order_spec.rb -e "outstanding_balance"
```

Expected: `NoMethodError: undefined method 'outstanding_balance'` en todos los ejemplos.

- [ ] **Step 3: Implementar el método en `app/models/order.rb`**

Localizar la sección de métodos de instancia (al final del archivo, antes del bloque `private` si existe). Agregar:

```ruby
  # Monto pendiente de cobrar para esta orden específica.
  # Solo considera pagos directamente vinculados via order_id.
  # Los pagos sueltos del cliente (sin order_id) no se descontan aquí.
  def outstanding_balance
    return 0 unless credit_order_type?

    total_amount - payments.sum(:amount)
  end
```

- [ ] **Step 4: Correr los tests del método**

```bash
bundle exec rspec spec/models/order_spec.rb -e "outstanding_balance"
```

Expected: todos los nuevos ejemplos verdes.

- [ ] **Step 5: Correr la suite completa**

```bash
bundle exec rspec
```

Expected: suite completa verde.

- [ ] **Step 6: Lint**

```bash
bundle exec rubocop app/models/order.rb spec/models/order_spec.rb
```

Expected: `no offenses detected`.

---

## Task 3: Fix `Payment#amount_within_order_total` — bug de sobrepago + tests

**Files:**
- Modify: `app/models/payment.rb`
- Test: `spec/models/payment_spec.rb`

**Contexto del bug:** La validación actual compara `amount > order.total_amount`. Si una orden de $200 ya tiene un pago de $150, se puede crear un segundo pago de $200 (pasa la validación pero genera $350 cobrados sobre $200).

- [ ] **Step 1: Agregar tests fallando para el caso de pago parcial previo**

Abrir `spec/models/payment_spec.rb`. Dentro del bloque `describe "amount_within_order_total"`, agregar después del último ejemplo existente:

```ruby
      context 'when order already has a partial payment' do
        let(:partial_order) do
          Sales::CreateOrder.call(
            customer: customer,
            items: [{ product_id: product.id, quantity: 2, unit_price: 100 }],
            order_type: 'credit',
            initial_payment: { amount: 50, payment_method: 'cash' }
          ).record
        end

        it 'is valid when amount covers remaining balance exactly' do
          payment = build(:payment, customer: customer, order: partial_order, amount: 150)
          expect(payment).to be_valid
        end

        it 'is invalid when amount exceeds remaining balance' do
          payment = build(:payment, customer: customer, order: partial_order, amount: 151)
          expect(payment).not_to be_valid
          expect(payment.errors[:amount].first).to match(/no puede exceder el saldo pendiente de la orden/)
        end

        it 'is valid when order is nil (standalone payment, any amount)' do
          payment = build(:payment, customer: customer, order: nil, amount: 999_999)
          expect(payment).to be_valid
        end
      end
```

- [ ] **Step 2: Correr los tests nuevos para verificar que fallan**

```bash
bundle exec rspec spec/models/payment_spec.rb -e "when order already has a partial payment"
```

Expected: el test de "exceeds remaining balance" pasa incorrectamente (bug activo) y el de "exactly" pasa. Confirmar que el caso `151` NO falla aún (eso es el bug).

- [ ] **Step 3: Actualizar el test existente que cambia de mensaje**

El test existente `"is invalid when amount exceeds order total"` espera el mensaje viejo. Actualizarlo para que coincida con el mensaje nuevo:

Reemplazar:
```ruby
      it "is invalid when amount exceeds order total" do
        payment = build(:payment, customer: customer, order: credit_order, amount: credit_order.total_amount + 1)
        expect(payment).not_to be_valid
        expect(payment.errors[:amount].first).to match(/no puede exceder el total de la orden/)
      end
```

Por:
```ruby
      it "is invalid when amount exceeds order total" do
        payment = build(:payment, customer: customer, order: credit_order, amount: credit_order.total_amount + 1)
        expect(payment).not_to be_valid
        expect(payment.errors[:amount].first).to match(/no puede exceder el saldo pendiente de la orden/)
      end
```

- [ ] **Step 4: Implementar el fix en `app/models/payment.rb`**

Reemplazar el método completo `amount_within_order_total`:

```ruby
  def amount_within_order_total
    return if amount.nil? || order.nil? || order.total_amount.nil?

    existing_paid = order.payments.where.not(id: id).sum(:amount)
    remaining = order.total_amount - existing_paid

    if amount > remaining
      errors.add(:amount, "no puede exceder el saldo pendiente de la orden ($#{remaining})")
    end
  end
```

Nota: `where.not(id: id)` excluye el registro actual para que la validación funcione correctamente tanto en `create` (id = nil, `where.not(id: nil)` excluye nada) como en `update` (excluye el propio pago).

- [ ] **Step 5: Correr el spec completo del modelo**

```bash
bundle exec rspec spec/models/payment_spec.rb
```

Expected: todos los ejemplos verdes, incluyendo los nuevos y el actualizado.

- [ ] **Step 6: Correr la suite completa**

```bash
bundle exec rspec
```

Expected: suite completa verde.

- [ ] **Step 7: Lint**

```bash
bundle exec rubocop app/models/payment.rb spec/models/payment_spec.rb
```

Expected: `no offenses detected`.

---

## Task 4: `Customer` — scope + helpers de deuda + tests

**Files:**
- Modify: `app/models/customer.rb`
- Test: `spec/models/customer_spec.rb` (crear si no existe)

- [ ] **Step 1: Verificar si existe `spec/models/customer_spec.rb`**

```bash
ls spec/models/customer_spec.rb
```

Si no existe, crear con este contenido base:

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Customer, type: :model do
end
```

- [ ] **Step 2: Escribir tests fallando para el scope y los helpers**

Dentro del bloque `RSpec.describe Customer` en `spec/models/customer_spec.rb`, agregar:

```ruby
  describe '.with_outstanding_balance' do
    let!(:stock_location) { create(:stock_location) }
    let(:product) { create(:product, current_stock: 50, price_unit: 100) }

    let(:debtor) { create(:customer, :with_credit) }
    let(:paid_up) { create(:customer, :with_credit) }
    let(:no_credit) { create(:customer, has_credit_account: false) }

    before do
      # debtor: orden de $200, sin pagos
      Sales::CreateOrder.call(
        customer: debtor,
        items: [{ product_id: product.id, quantity: 2, unit_price: 100 }],
        order_type: 'credit'
      )

      # paid_up: orden de $100, pagada completamente
      Sales::CreateOrder.call(
        customer: paid_up,
        items: [{ product_id: product.id, quantity: 1, unit_price: 100 }],
        order_type: 'credit',
        initial_payment: { amount: 100, payment_method: 'cash' }
      )
    end

    it 'includes customers with outstanding balance' do
      expect(Customer.with_outstanding_balance).to include(debtor)
    end

    it 'excludes customers with zero balance' do
      expect(Customer.with_outstanding_balance).not_to include(paid_up)
    end

    it 'excludes customers without credit account' do
      expect(Customer.with_outstanding_balance).not_to include(no_credit)
    end

    it 'excludes "Cliente Mostrador"' do
      expect(Customer.with_outstanding_balance.map(&:name)).not_to include('Cliente Mostrador')
    end
  end

  describe '#last_payment_date' do
    let(:customer) { create(:customer, :with_credit) }

    it 'returns nil when no payments exist' do
      expect(customer.last_payment_date).to be_nil
    end

    it 'returns the most recent payment date' do
      create(:payment, customer: customer, payment_date: 5.days.ago.to_date)
      create(:payment, customer: customer, payment_date: 2.days.ago.to_date)
      expect(customer.last_payment_date).to eq(2.days.ago.to_date)
    end
  end

  describe '#days_without_paying' do
    let(:customer) { create(:customer, :with_credit) }

    it 'returns nil when no payments exist' do
      expect(customer.days_without_paying).to be_nil
    end

    it 'returns 0 when last payment is today' do
      create(:payment, customer: customer, payment_date: Date.today)
      expect(customer.days_without_paying).to eq(0)
    end

    it 'returns number of days since last payment' do
      create(:payment, customer: customer, payment_date: 7.days.ago.to_date)
      expect(customer.days_without_paying).to eq(7)
    end
  end
```

- [ ] **Step 3: Correr los tests para verificar que fallan**

```bash
bundle exec rspec spec/models/customer_spec.rb
```

Expected: fallos por métodos/scopes no definidos.

- [ ] **Step 4: Implementar el scope y los helpers en `app/models/customer.rb`**

En la sección de `# Scopes`, agregar después del scope existente `scope :stores`:

```ruby
  scope :with_outstanding_balance, -> {
    with_credit_account
      .where(
        "( SELECT COALESCE(SUM(o.total_amount), 0)
           FROM orders o
           WHERE o.customer_id = customers.id
             AND o.order_type = 'credit'
             AND o.status = 'confirmed' )
         >
         ( SELECT COALESCE(SUM(p.amount), 0)
           FROM payments p
           WHERE p.customer_id = customers.id )"
      )
  }
```

Después del método `current_balance`, agregar los dos helpers:

```ruby
  def last_payment_date
    payments.maximum(:payment_date)
  end

  def days_without_paying
    return nil if last_payment_date.nil?

    (Date.today - last_payment_date).to_i
  end
```

- [ ] **Step 5: Correr el spec del modelo**

```bash
bundle exec rspec spec/models/customer_spec.rb
```

Expected: todos los ejemplos verdes.

- [ ] **Step 6: Correr la suite completa**

```bash
bundle exec rspec
```

Expected: suite completa verde.

- [ ] **Step 7: Lint**

```bash
bundle exec rubocop app/models/customer.rb spec/models/customer_spec.rb
```

Expected: `no offenses detected`.

---

## Task 5: `CustomerPolicy`, ruta y acción `debtors`

**Files:**
- Modify: `app/policies/customer_policy.rb`
- Modify: `config/routes.rb`
- Modify: `app/controllers/web/customers_controller.rb`
- Test: `spec/requests/web/customers_spec.rb` (crear si no existe)

- [ ] **Step 1: Crear/abrir el request spec y escribir tests fallando**

Si `spec/requests/web/customers_spec.rb` no existe, crearlo. Agregar:

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Web::Customers', type: :request do
  let!(:stock_location) { create(:stock_location) }
  let(:admin) { create(:user, role: 'admin') }
  let(:product) { create(:product, current_stock: 50, price_unit: 100) }

  before { sign_in admin }

  describe 'GET /web/customers/debtors' do
    let!(:debtor) { create(:customer, :with_credit) }
    let!(:paid_customer) { create(:customer, :with_credit) }
    let!(:no_credit_customer) { create(:customer, has_credit_account: false) }

    before do
      # debtor: orden sin pagar
      Sales::CreateOrder.call(
        customer: debtor,
        items: [{ product_id: product.id, quantity: 2, unit_price: 100 }],
        order_type: 'credit'
      )

      # paid_customer: orden completamente pagada
      Sales::CreateOrder.call(
        customer: paid_customer,
        items: [{ product_id: product.id, quantity: 1, unit_price: 100 }],
        order_type: 'credit',
        initial_payment: { amount: 100, payment_method: 'cash' }
      )
    end

    it 'returns 200' do
      get debtors_web_customers_path
      expect(response).to have_http_status(:ok)
    end

    it 'includes customers with outstanding balance' do
      get debtors_web_customers_path
      expect(response.body).to include(debtor.name)
    end

    it 'excludes customers with zero balance' do
      get debtors_web_customers_path
      expect(response.body).not_to include(paid_customer.name)
    end

    it 'excludes customers without credit account' do
      get debtors_web_customers_path
      expect(response.body).not_to include(no_credit_customer.name)
    end
  end
end
```

- [ ] **Step 2: Correr el spec para verificar que falla**

```bash
bundle exec rspec spec/requests/web/customers_spec.rb
```

Expected: `NameError: undefined local variable or method 'debtors_web_customers_path'` o `ActionController::RoutingError`.

- [ ] **Step 3: Agregar la ruta en `config/routes.rb`**

Localizar el bloque de `resources :customers`. Reemplazar:

```ruby
    resources :customers, only: [ :index, :new, :create, :show, :edit, :update ] do
      resources :payments, only: [ :new, :create ], module: :customers
    end
```

Por:

```ruby
    resources :customers, only: [ :index, :new, :create, :show, :edit, :update ] do
      collection do
        get :debtors
      end
      resources :payments, only: [ :new, :create ], module: :customers
    end
```

- [ ] **Step 4: Agregar `debtors?` en `app/policies/customer_policy.rb`**

Agregar después del método `index?`:

```ruby
  def debtors?
    index?
  end
```

- [ ] **Step 5: Agregar la acción `debtors` en `app/controllers/web/customers_controller.rb`**

Agregar después del método `index`:

```ruby
    def debtors
      authorize Customer, :debtors?
      @debtors = Customer.with_outstanding_balance.to_a.sort_by { |c| -c.current_balance }
    end
```

- [ ] **Step 6: Correr el request spec**

```bash
bundle exec rspec spec/requests/web/customers_spec.rb
```

Expected: falla con `ActionView::MissingTemplate` (la ruta existe pero no hay vista aún). Ese error confirma que la ruta y el controller funcionan — la vista se crea en Task 10.

- [ ] **Step 7: Correr la suite completa**

```bash
bundle exec rspec
```

Expected: solo el request spec de debtors falla por vista faltante; el resto verde.

- [ ] **Step 8: Lint**

```bash
bundle exec rubocop app/policies/customer_policy.rb config/routes.rb app/controllers/web/customers_controller.rb
```

Expected: `no offenses detected`.

---

## Task 6: `orders/show` — fix links de cliente + sección pagos de la venta

**Files:**
- Modify: `app/views/web/orders/show.html.haml`

Esta es una tarea puramente de vista — no tiene tests de unidad. Se verifica con `bundle exec rspec` (asegura no rompió nada) y visualmente.

- [ ] **Step 1: Fix link del cliente en la card principal (línea ~49)**

Localizar en `app/views/web/orders/show.html.haml` la línea:

```haml
                = link_to @order.customer.name, "#", class: "text-base font-medium text-blue-600 hover:text-blue-800 hover:underline"
```

Reemplazarla por:

```haml
                = link_to @order.customer.name, web_customer_path(@order.customer), class: "text-base font-medium text-blue-600 hover:text-blue-800 hover:underline"
```

- [ ] **Step 2: Fix link del cliente en el sidebar derecho (línea ~267)**

Localizar la línea:

```haml
            = link_to @order.customer.name, "#", class: "text-sm font-medium text-blue-600 hover:text-blue-800 hover:underline block mb-2"
```

Reemplazarla por:

```haml
            = link_to @order.customer.name, web_customer_path(@order.customer), class: "text-sm font-medium text-blue-600 hover:text-blue-800 hover:underline block mb-2"
```

- [ ] **Step 3: Agregar sección "Pagos de esta Venta" en el sidebar derecho**

Localizar el bloque que comienza con:

```haml
        -# Info del cliente (solo si es venta a crédito)
        - if @order.credit_order_type? && @order.customer
          .border-t.border-gray-200.py-4
```

Inmediatamente DESPUÉS del cierre de ese bloque (antes del bloque `Botón de acción`), agregar:

```haml
        -# Pagos de esta venta (solo crédito)
        - if @order.credit_order_type?
          .border-t.border-gray-200.py-4
            %h4.text-sm.font-semibold.text-gray-900.mb-3 Pagos de esta Venta

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
                .flex.justify-between.text-sm
                  %span.text-gray-600 Pendiente
                  - pending = @order.outstanding_balance
                  %span.font-bold{ class: pending > 0 ? 'text-amber-600' : 'text-emerald-600' }
                    = currency_ar(pending)
            - else
              %p.text-xs.text-gray-400.italic Sin cobros registrados para esta venta
              %p.text-xs.text-gray-400.mt-1.italic Los abonos sueltos del cliente se reflejan en el saldo total.
```

- [ ] **Step 4: Asegurar que `@order.payments` no genera N+1**

Abrir `app/controllers/web/orders_controller.rb` y verificar la acción `show`. Agregar `includes(:payments)` si no está:

```ruby
    def show
      @order = Order.includes(:order_items => :product, :stock_movements => [:product, :stock_location], :payments).find(params[:id])
      @order_items = @order.order_items
      @stock_movements = @order.stock_movements
    end
```

Si el controller ya usa `set_order` o similar, ajustar en consecuencia. Lo importante es que `@order.payments` esté precargado.

- [ ] **Step 5: Correr la suite completa**

```bash
bundle exec rspec
```

Expected: suite verde (las vistas no tienen tests de unidad, pero los specs existentes no deben romperse).

- [ ] **Step 6: Lint**

```bash
bundle exec rubocop app/views/web/orders/show.html.haml app/controllers/web/orders_controller.rb 2>/dev/null || echo "rubocop no analiza HAML"
bundle exec rubocop app/controllers/web/orders_controller.rb
```

Expected: `no offenses detected` en el controller.

---

## Task 7: `customers/show` — órdenes clickeables + columnas Cobrado/Pendiente

**Files:**
- Modify: `app/views/web/customers/show.html.haml`
- Modify: `app/controllers/web/customers_controller.rb` (agregar `includes`)

- [ ] **Step 1: Agregar `includes(:payments)` en la query de la acción `show`**

En `app/controllers/web/customers_controller.rb`, localizar la acción `show`:

```ruby
    def show
      authorize @customer
      @credit_orders = @customer.orders
                                .where(order_type: "credit")
                                .where.not(status: "cancelled")
                                .order(created_at: :desc)
      @payments = @customer.payments.order(payment_date: :desc)
      @current_balance = @customer.current_balance
    end
```

Agregar `.includes(:payments)` a la query de `@credit_orders`:

```ruby
    def show
      authorize @customer
      @credit_orders = @customer.orders
                                .where(order_type: "credit")
                                .where.not(status: "cancelled")
                                .includes(:payments)
                                .order(created_at: :desc)
      @payments = @customer.payments.order(payment_date: :desc)
      @current_balance = @customer.current_balance
    end
```

- [ ] **Step 2: Actualizar la tabla de "Ventas a Crédito" en `customers/show.html.haml`**

Localizar el bloque de la tabla de órdenes. Reemplazar el `%table` completo de Ventas a Crédito:

```haml
          .overflow-x-auto
            %table.min-w-full.divide-y.divide-slate-200
              %thead
                %tr
                  %th.px-3.py-2.text-left.text-xs.font-medium.text-slate-500.uppercase.tracking-wider Fecha
                  %th.px-3.py-2.text-right.text-xs.font-medium.text-slate-500.uppercase.tracking-wider Total
                  %th.px-3.py-2.text-center.text-xs.font-medium.text-slate-500.uppercase.tracking-wider Estado

              %tbody.divide-y.divide-slate-100
                - @credit_orders.each do |order|
                  %tr.hover:bg-slate-50.transition-colors
                    %td.px-3.py-2.whitespace-nowrap.text-sm.text-slate-700
                      = l(order.sale_date || order.created_at.to_date, format: :default)
                    %td.px-3.py-2.whitespace-nowrap.text-right.text-sm.font-semibold.text-slate-900
                      = currency_ar_int(order.total_amount)
                    %td.px-3.py-2.whitespace-nowrap.text-center
                      - if order.confirmed_status?
                        %span.inline-flex.items-center.px-2.py-0.5.rounded-md.text-xs.font-medium.bg-blue-100.text-blue-800
                          Confirmada
                      - else
                        %span.inline-flex.items-center.px-2.py-0.5.rounded-md.text-xs.font-medium.bg-slate-100.text-slate-600
                          = order.status
```

Por:

```haml
          .overflow-x-auto
            %table.min-w-full.divide-y.divide-slate-200
              %thead
                %tr
                  %th.px-3.py-2.text-left.text-xs.font-medium.text-slate-500.uppercase.tracking-wider Fecha
                  %th.px-3.py-2.text-right.text-xs.font-medium.text-slate-500.uppercase.tracking-wider Total
                  %th.px-3.py-2.text-right.text-xs.font-medium.text-slate-500.uppercase.tracking-wider Cobrado
                  %th.px-3.py-2.text-right.text-xs.font-medium.text-slate-500.uppercase.tracking-wider Pendiente
                  %th.px-3.py-2.text-center.text-xs.font-medium.text-slate-500.uppercase.tracking-wider Estado

              %tbody.divide-y.divide-slate-100
                - @credit_orders.each do |order|
                  = link_to web_order_path(order), class: "table-row hover:bg-slate-50 transition-colors" do
                    %td.px-3.py-2.whitespace-nowrap.text-sm.text-slate-700
                      = l(order.sale_date || order.created_at.to_date, format: :default)
                    %td.px-3.py-2.whitespace-nowrap.text-right.text-sm.font-semibold.text-slate-900
                      = currency_ar_int(order.total_amount)
                    %td.px-3.py-2.whitespace-nowrap.text-right.text-sm.text-emerald-700
                      = currency_ar_int(order.payments.sum(:amount))
                    %td.px-3.py-2.whitespace-nowrap.text-right.text-sm
                      - pending = order.outstanding_balance
                      %span{ class: pending > 0 ? 'font-semibold text-amber-600' : 'text-slate-400' }
                        = currency_ar_int(pending)
                    %td.px-3.py-2.whitespace-nowrap.text-center
                      - if order.outstanding_balance == 0
                        %span.inline-flex.items-center.px-2.py-0.5.rounded-md.text-xs.font-medium.bg-emerald-100.text-emerald-800
                          Al día
                      - else
                        %span.inline-flex.items-center.px-2.py-0.5.rounded-md.text-xs.font-medium.bg-amber-100.text-amber-700
                          Pendiente
```

- [ ] **Step 3: Agregar nota aclaratoria sobre pagos sueltos**

Inmediatamente después del cierre del bloque de la tabla (después del `- else` con el mensaje "No hay ventas"), agregar una nota al pie:

```haml
          %p.text-xs.text-slate-400.italic.mt-2
            * El saldo pendiente por venta solo refleja cobros vinculados directamente a esa venta. Los abonos a cuenta se descuentan del saldo total del cliente.
```

- [ ] **Step 4: Correr la suite completa**

```bash
bundle exec rspec
```

Expected: suite verde.

- [ ] **Step 5: Lint**

```bash
bundle exec rubocop app/controllers/web/customers_controller.rb
```

Expected: `no offenses detected`.

---

## Task 8: `customers/index` — columna Saldo

**Files:**
- Modify: `app/views/web/customers/index.html.haml`

- [ ] **Step 1: Agregar columna "Saldo" en el `%thead`**

Localizar el `%thead` de la tabla de clientes. Agregar una columna después de `Cuenta Corriente` y antes de `Acciones`:

```haml
            %th.px-4.py-3.text-right.text-xs.font-medium.text-slate-500.uppercase.tracking-wider
              Saldo
```

- [ ] **Step 2: Agregar celda de saldo en cada fila del `%tbody`**

Localizar el loop `- @customers.each do |customer|`. Agregar la celda de saldo después de la celda de "Cuenta corriente" y antes de la celda de "Acciones":

```haml
              -# Saldo
              %td.px-4.py-3.whitespace-nowrap.text-right
                - if customer.has_credit_account?
                  - balance = customer.current_balance
                  - if balance == 0
                    %span.inline-flex.items-center.px-2.py-0.5.rounded-md.text-xs.font-medium.bg-emerald-100.text-emerald-800
                      Al día
                  - else
                    %span.text-sm.font-semibold.text-amber-600
                      = currency_ar_int(balance)
                - else
                  %span.text-xs.text-slate-400 —
```

- [ ] **Step 3: Correr la suite completa**

```bash
bundle exec rspec
```

Expected: suite verde.

---

## Task 9: Sidebar — extender grupo Ventas y grupo Clientes

**Files:**
- Modify: `app/views/layouts/web/_sidebar.html.haml`

- [ ] **Step 1: Extender el grupo Ventas para incluir "Ventas del Sistema"**

Localizar el bloque del grupo Ventas. El submenu actual tiene solo "Ventas Importadas" y "Reportes". Agregar "Ventas del Sistema" como primer item:

```haml
      .nav-submenu.pl-8.border-l-2.border-slate-200.ml-4{ data: { dropdown_target: "menu" } }
        = link_to web_orders_path, class: "nav-subitem #{controller_name == 'orders' ? 'active' : ''}" do
          %span.text-base 🧾
          %span Ventas del Sistema

        = link_to web_sales_ledger_imports_path, class: "nav-subitem #{controller_name == 'imports' ? 'active' : ''}" do
          %span.text-base 📋
          %span Ventas Importadas

        = link_to web_sales_ledger_reports_path, class: "nav-subitem #{controller_name == 'reports' ? 'active' : ''}" do
          %span.text-base 📊
          %span Reportes
```

También actualizar la condición del grupo Ventas para que se marque activo cuando se esté en `orders`:

Localizar:
```haml
    - ventas_active = controller_path.start_with?('web/sales_ledger')
```

Reemplazar por:
```haml
    - ventas_active = controller_path.start_with?('web/sales_ledger') || controller_name == 'orders'
```

- [ ] **Step 2: Convertir el link de Clientes en grupo con submenu**

Localizar el link de Clientes (actualmente un link directo):

```haml
    = link_to web_customers_path, class: "flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium #{controller_name == 'customers' ? 'text-slate-900 bg-slate-100' : 'text-slate-600 hover:text-slate-900 hover:bg-slate-50 transition-colors'}" do
      %span.text-base 👥
      %span Clientes
```

Reemplazarlo por un grupo con submenu (mismo patrón que Ventas y Facturación):

```haml
    -# Clientes (con submenu)
    - clientes_active = controller_name == 'customers'
    - debtors_count = Customer.with_outstanding_balance.count
    .nav-group{ data: { controller: "dropdown" } }
      %button.nav-item.nav-group-toggle{
        type: "button",
        data: { action: "click->dropdown#toggle" },
        class: (clientes_active ? 'bg-slate-100' : '')
      }
        .flex.items-center.justify-between.w-full
          .flex.items-center.gap-3
            .nav-icon
              %span.text-base 👥
            %span.font-medium.text-slate-900 Clientes
          .nav-arrow{ data: { dropdown_target: "arrow" } }
            ▼

      .nav-submenu.pl-8.border-l-2.border-slate-200.ml-4{ data: { dropdown_target: "menu" } }
        = link_to web_customers_path, class: "nav-subitem #{(controller_name == 'customers' && action_name != 'debtors') ? 'active' : ''}" do
          %span.text-base 👤
          %span Todos los Clientes

        = link_to debtors_web_customers_path, class: "nav-subitem #{(controller_name == 'customers' && action_name == 'debtors') ? 'active' : ''}" do
          .flex.items-center.justify-between.w-full
            .flex.items-center.gap-2
              %span.text-base 💳
              %span Cuentas por Cobrar
            - if debtors_count > 0
              %span.inline-flex.items-center.justify-center.w-5.h-5.rounded-full.bg-amber-100.text-amber-700.text-xs.font-bold
                = debtors_count
```

- [ ] **Step 3: Correr la suite completa**

```bash
bundle exec rspec
```

Expected: suite verde. Si hay errores de `NameError` en el sidebar por `debtors_web_customers_path`, verificar que la ruta fue agregada correctamente en Task 5.

---

## Task 10: Vista `customers/debtors` (nueva)

**Files:**
- Create: `app/views/web/customers/debtors.html.haml`

- [ ] **Step 1: Crear la vista**

Crear `app/views/web/customers/debtors.html.haml` con el siguiente contenido:

```haml
- content_for :page_title, "Cuentas por Cobrar"

- customer_type_labels = { "retail" => "Minorista", "workshop" => "Taller", "mechanic" => "Mecánico", "store" => "Tienda" }

.container.mx-auto.px-6.py-6

  -# Header
  .flex.items-center.justify-between.mb-6
    %div
      %h1.text-3xl.font-bold.text-gray-900 Cuentas por Cobrar
      %p.text-sm.text-slate-500.mt-1 Clientes con saldo pendiente, ordenados por deuda

  -# Mensajes
  - if flash[:notice]
    .bg-green-50.border-l-4.border-green-500.p-4.rounded-lg.mb-6.flex.items-start.gap-3
      .w-10.h-10.rounded-xl.bg-green-500.flex.items-center.justify-center.text-white.flex-shrink-0
        ✓
      .flex-1
        %p.text-sm.text-green-700= flash[:notice]

  - if @debtors.any?
    .bg-white.border.border-slate-200.rounded-lg.overflow-hidden
      %table.min-w-full.divide-y.divide-slate-200
        %thead.bg-slate-50
          %tr
            %th.px-4.py-3.text-left.text-xs.font-medium.text-slate-500.uppercase.tracking-wider
              Cliente
            %th.px-4.py-3.text-left.text-xs.font-medium.text-slate-500.uppercase.tracking-wider
              Tipo
            %th.px-4.py-3.text-right.text-xs.font-medium.text-slate-500.uppercase.tracking-wider
              Saldo
            %th.px-4.py-3.text-center.text-xs.font-medium.text-slate-500.uppercase.tracking-wider
              Último Pago
            %th.px-4.py-3.text-center.text-xs.font-medium.text-slate-500.uppercase.tracking-wider
              Sin pagar
            %th.px-4.py-3.text-center.text-xs.font-medium.text-slate-500.uppercase.tracking-wider
              Acciones

        %tbody.divide-y.divide-slate-100.bg-white
          - @debtors.each do |customer|
            - days = customer.days_without_paying
            - last_date = customer.last_payment_date
            %tr.hover:bg-slate-50.transition-colors
              -# Cliente
              %td.px-4.py-3.whitespace-nowrap
                .flex.items-center.gap-3
                  .w-9.h-9.rounded-lg.bg-slate-100.flex.items-center.justify-center.text-lg.flex-shrink-0
                    👤
                  = link_to customer.name, web_customer_path(customer), class: "text-sm font-semibold text-slate-900 hover:text-slate-600 hover:underline"

              -# Tipo
              %td.px-4.py-3.whitespace-nowrap
                %span.inline-flex.items-center.px-2.5.py-1.rounded-md.text-xs.font-medium.bg-slate-100.text-slate-700
                  = customer_type_labels[customer.customer_type] || customer.customer_type

              -# Saldo
              %td.px-4.py-3.whitespace-nowrap.text-right
                %span.text-base.font-bold.text-amber-600
                  = currency_ar_int(customer.current_balance)

              -# Último pago
              %td.px-4.py-3.whitespace-nowrap.text-center
                - if last_date
                  %span.text-sm.text-slate-600= l(last_date, format: :default)
                - else
                  %span.text-xs.text-slate-400.italic Sin pagos

              -# Días sin pagar
              %td.px-4.py-3.whitespace-nowrap.text-center
                - if days.nil?
                  %span.inline-flex.items-center.px-2.py-0.5.rounded-md.text-xs.font-medium.bg-red-100.text-red-700
                    Sin pagos
                - elsif days > 30
                  %span.inline-flex.items-center.px-2.py-0.5.rounded-md.text-xs.font-medium.bg-red-100.text-red-700
                    = "#{days} días"
                - elsif days > 15
                  %span.inline-flex.items-center.px-2.py-0.5.rounded-md.text-xs.font-medium.bg-amber-100.text-amber-700
                    = "#{days} días"
                - else
                  %span.inline-flex.items-center.px-2.py-0.5.rounded-md.text-xs.font-medium.bg-slate-100.text-slate-600
                    = days == 0 ? 'Hoy' : "#{days} días"

              -# Acciones
              %td.px-4.py-3.whitespace-nowrap.text-center
                .flex.items-center.justify-center.gap-2
                  = link_to web_customer_path(customer), class: "inline-flex items-center justify-center w-8 h-8 text-slate-400 hover:text-slate-600 hover:bg-slate-100 rounded-lg transition-colors", title: "Ver detalle" do
                    %span 👁️
                  - if policy(Payment.new(customer: customer)).new?
                    = link_to new_web_customer_payment_path(customer), class: "inline-flex items-center justify-center px-3 py-1.5 text-xs font-semibold bg-slate-700 hover:bg-slate-800 text-white rounded-lg transition-colors" do
                      + Pago

  - else
    .bg-white.border.border-slate-200.rounded-lg.p-16.text-center
      .inline-flex.w-20.h-20.rounded-full.bg-emerald-100.items-center.justify-center.text-4xl.mb-4
        ✓
      %h3.text-xl.font-bold.text-slate-900.mb-2 Todos al día
      %p.text-slate-500 No hay clientes con saldo pendiente en este momento.
      = link_to web_customers_path, class: "inline-flex items-center gap-2 mt-6 px-4 py-2 border border-slate-300 text-slate-700 text-sm font-semibold rounded-lg hover:bg-slate-50 transition-colors" do
        ← Ver todos los clientes
```

- [ ] **Step 2: Correr el request spec de debtors**

```bash
bundle exec rspec spec/requests/web/customers_spec.rb
```

Expected: todos los ejemplos verdes ahora que la vista existe.

- [ ] **Step 3: Correr la suite completa**

```bash
bundle exec rspec
```

Expected: suite completa verde.

---

## Task 11: Dashboard — link en métrica "Por Cobrar"

**Files:**
- Modify: `app/views/web/dashboard/index.html.haml`

- [ ] **Step 1: Envolver la card de "Por Cobrar" en un link**

Localizar en `app/views/web/dashboard/index.html.haml` el bloque de la card "Cuentas por Cobrar":

```haml
  -# Cuentas por Cobrar
  .bg-white.border.border-slate-200.rounded-lg.p-6
    .flex.items-start.justify-between.mb-4
      .flex-1
        %p.text-xs.font-medium.text-slate-500.uppercase.tracking-wide.mb-2 Por Cobrar
        %h3.text-3xl.font-bold.text-slate-900= currency_ar_int(@total_receivable)
      .w-10.h-10.bg-blue-100.rounded-lg.flex.items-center.justify-center.text-xl
        📋
    .flex.items-center.gap-2.text-sm
      - customers_count = Customer.with_credit_account.count
      %span.text-slate-500= "#{customers_count} #{'cliente'.pluralize(customers_count)}"
```

Reemplazarlo por (agrega el link y actualiza el subtexto para mostrar deudores):

```haml
  -# Cuentas por Cobrar
  = link_to debtors_web_customers_path, class: "block bg-white border border-slate-200 rounded-lg p-6 hover:border-slate-300 hover:shadow-sm transition-all" do
    .flex.items-start.justify-between.mb-4
      .flex-1
        %p.text-xs.font-medium.text-slate-500.uppercase.tracking-wide.mb-2 Por Cobrar
        %h3.text-3xl.font-bold.text-slate-900= currency_ar_int(@total_receivable)
      .w-10.h-10.bg-blue-100.rounded-lg.flex.items-center.justify-center.text-xl
        📋
    .flex.items-center.gap-2.text-sm
      - debtors_count = Customer.with_outstanding_balance.count
      - if debtors_count > 0
        %span.text-amber-600.font-medium= "#{debtors_count} #{'cliente'.pluralize(debtors_count)} con deuda"
      - else
        %span.text-emerald-600.font-medium Todos al día
```

- [ ] **Step 2: Correr la suite completa**

```bash
bundle exec rspec
```

Expected: suite completa verde.

---

## Task 12: `WORKING_CONTEXT.md` — actualizar

**Files:**
- Modify: `WORKING_CONTEXT.md`

- [ ] **Step 1: Actualizar la sección "Web surface"**

Localizar la línea que describe `Customers`:

```markdown
* **Customers**: index/show/new/create/edit/update; nested **`payments`** new/create → `Payments::RegisterPayment` (module `Web::Customers`).
```

Reemplazarla por:

```markdown
* **Customers**: index/show/new/create/edit/update; **`debtors`** collection → lista de clientes con balance > 0 ordenada por deuda; nested **`payments`** new/create → `Payments::RegisterPayment` (module `Web::Customers`).
```

- [ ] **Step 2: Actualizar la sección "Customer account payments"**

Agregar al final de esa sección:

```markdown
* **`Order#outstanding_balance`** = `total_amount - order.payments.sum(:amount)` — solo cuenta pagos vinculados directamente a la orden (no pagos sueltos del cliente).
* **`Customer#last_payment_date`** / **`#days_without_paying`** — helpers para la vista de deudores.
* **`Customer.with_outstanding_balance`** scope — clientes cuyas ventas a crédito confirmadas superan el total de sus pagos.
* **`Payment#amount_within_order_total`** valida contra el saldo pendiente de la orden (`order.outstanding_balance` excluyendo el pago actual), no contra el total. Fix de bug: antes comparaba contra `total_amount`.
```

- [ ] **Step 3: Verificar el diff**

```bash
git diff WORKING_CONTEXT.md
```

Expected: solo las dos modificaciones anteriores.

---

## Task 13: Verificación final

**Files:** ninguno.

- [ ] **Step 1: Suite completa una última vez**

```bash
bundle exec rspec
```

Expected: toda la suite verde. Anotar el número de ejemplos para confirmar que no se perdió ningún test.

- [ ] **Step 2: Lint global**

```bash
bundle exec rubocop
```

Expected: `no offenses detected`. Si hay offenses introducidos en este feature, correr `bundle exec rubocop -a` sobre los archivos afectados.

- [ ] **Step 3: Verificación manual del flujo principal**

Levantar `bin/dev` (o `bundle exec rails s`), ir a `http://localhost:3000` y verificar:

1. **Sidebar:** el grupo "Ventas" tiene "Ventas del Sistema" como primer item → navega a la lista de órdenes.
2. **Sidebar:** "Clientes" es ahora un grupo con "Todos los Clientes" y "Cuentas por Cobrar".
3. **Cuentas por Cobrar:** muestra la tabla de deudores con saldo, último pago, días sin pagar. El botón "+ Pago" por fila navega al form de pago.
4. **customers/index:** la columna "Saldo" muestra "Al día" en verde o el monto en ámbar según corresponda.
5. **customers/show:** las filas de ventas a crédito son clickeables y muestran columnas Cobrado/Pendiente. El estado "Pendiente" / "Al día" refleja los pagos vinculados.
6. **orders/show:** el nombre del cliente en la card de info y en el sidebar derecho navegan al perfil del cliente. La sección "Pagos de esta Venta" aparece en órdenes a crédito.
7. **Dashboard:** la card "Por Cobrar" es clickeable y navega a "Cuentas por Cobrar".

- [ ] **Step 4: Commit único del feature**

```bash
git add -A
git status  # revisar que solo están los archivos esperados
git commit -m "feat (feat_05): add customer debt visibility

- Order#outstanding_balance: computed from linked payments only
- Fix Payment#amount_within_order_total: validate against remaining balance
- Customer.with_outstanding_balance scope + last_payment_date/days_without_paying helpers
- customers/debtors page: debtors sorted by balance with days-without-paying indicator
- customers/index: saldo column
- customers/show: clickable credit orders with Cobrado/Pendiente columns
- orders/show: fix broken customer links; add linked payments section
- Sidebar: Ventas del Sistema link; Clientes group with Cuentas por Cobrar submenu
- Dashboard: Por Cobrar card links to debtors page"
```

---

## Notas para el ejecutor

- **Orden estricto:** modelos → policies/routes/controller → vistas. No saltear tareas.
- **Si un task falla a mitad:** dejar el trabajo sin commitear, pasar el contexto al siguiente loop. No commitear trabajo parcial.
- **Tests pre-existentes que rompen:** detenerse y avisar al usuario — probablemente sea un cambio de comportamiento involuntario.
- **El sidebar usa un query inline** (`Customer.with_outstanding_balance.count`) que se ejecuta en cada request. Aceptable para el volumen actual. Si se convierte en problema de performance, moverlo a un `before_action` en `ApplicationController`.
- **`link_to` como `table-row`:** usar `class: "table-row"` para que el link ocupe toda la fila. Verificar que el CSS de Tailwind no bloquee este uso.
