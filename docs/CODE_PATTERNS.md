# CODE_PATTERNS.md

**Patrones de Código Esenciales - Sistema de Gestión de Repuestos**

Ejemplos concisos de patrones clave. Para reglas completas, consultar `DEVELOPMENT_GUIDE.md`.

---

## 1. SERVICES - Patrón Base

### Result Struct (usar en todos los services)

```ruby
# app/services/result.rb
Result = Struct.new(:success?, :record, :errors, keyword_init: true) do
  def failure?
    !success?
  end
end
```

### Estructura de Service Estándar

```ruby
# app/services/[dominio]/[accion].rb
module Sales
  class CreateOrder
    def initialize(customer:, items:, order_type:, user:)
      @customer = customer
      @items = items
      @order_type = order_type
      @user = user
    end

    def call
      validate_params
      
      ActiveRecord::Base.transaction do
        create_order
        create_related_records
        
        Result.new(success?: true, record: @order, errors: [])
      end
    rescue ValidationError => e
      Result.new(success?: false, record: nil, errors: [e.message])
    rescue StandardError => e
      Rails.logger.error("Error in CreateOrder: #{e.message}")
      Result.new(success?: false, record: nil, errors: ['Error al crear la venta'])
    end

    private

    class ValidationError < StandardError; end

    def validate_params
      raise ValidationError, 'mensaje' if condicion_invalida
    end

    def create_order
      @order = Order.create!(attrs)
    end
  end
end
```

### Uso desde Controller

```ruby
def create
  result = Sales::CreateOrder.new(
    customer: @customer,
    items: parse_items,
    order_type: params[:order_type],
    user: current_user
  ).call

  if result.success?
    redirect_to result.record, notice: "Creado exitosamente"
  else
    flash.now[:alert] = result.errors.join(", ")
    render :new, status: :unprocessable_entity
  end
end
```

---

## 2. MODELS - Patrones Clave

### Validaciones y Scopes Comunes

```ruby
class Product < ApplicationRecord
  # Asociaciones
  has_many :stock_movements
  belongs_to :category, optional: true

  # Validaciones
  validates :code, presence: true, uniqueness: true
  validates :name, presence: true
  validates :sale_price, numericality: { greater_than_or_equal_to: 0 }
  validates :status, inclusion: { in: %w[active inactive] }

  # Scopes útiles
  scope :active, -> { where(status: 'active') }
  scope :with_low_stock, -> { where('current_stock < ?', 5) }
  scope :search, ->(query) {
    where('code ILIKE ? OR name ILIKE ?', "%#{query}%", "%#{query}%") if query.present?
  }

  # Stock cacheado:
  # - current_stock es una columna en products
  # - SOLO se debe modificar desde services de inventario
  # - NUNCA desde controllers o vistas
  def recalculate_current_stock!
    update!(current_stock: stock_movements.sum(:quantity))
  end

  def low_stock?
    current_stock.to_i < 5
  end
end
```

### Cálculo de Saldo de Cliente

```ruby
class Customer < ApplicationRecord
  has_many :orders
  has_many :payments

  def current_balance
    return 0 unless has_credit_account?
    
    total_credit_sales = orders
                          .where(order_type: 'credit', status: 'active')
                          .sum(:total)
    
    total_payments = payments.sum(:amount)
    
    total_credit_sales - total_payments
  end
end
```

---

## 3. CONTROLLERS - Patrón Estándar

### Controller Típico (thin controller)

```ruby
class ProductsController < ApplicationController
  before_action :set_product, only: [:show, :edit, :update]

  def index
    @products = Product.active
                       .search(params[:q])
                       .page(params[:page])
  end

  def create
    @product = Product.new(product_params)

    if @product.save
      redirect_to @product, notice: "Producto creado"
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def set_product
    @product = Product.find(params[:id])
  end

  def product_params
    params.require(:product).permit(:code, :name, :sale_price)
  end
end
```

### Controller con Service

```ruby
class OrdersController < ApplicationController
  def create
    result = Sales::CreateOrder.new(
      customer: find_customer,
      items: parse_items,
      order_type: order_params[:order_type],
      user: current_user
    ).call

    if result.success?
      redirect_to result.record, notice: "Venta registrada"
    else
      flash.now[:alert] = result.errors.join(", ")
      render :new, status: :unprocessable_entity
    end
  end
end
```

---

## 4. VIEWS HAML - Snippets Útiles

### Estructura de Vista Típica

```haml
-# app/views/web/products/index.html.haml

.container.mx-auto.px-6.py-8
  -# Header
  .flex.justify-between.items-center.mb-6
    %h1.text-3xl.font-bold.text-gray-900 Productos
    = link_to new_product_path, class: "btn-primary" do
      Nuevo Producto

  -# Filtros/Búsqueda
  .card.mb-6
    = form_with url: products_path, method: :get do |f|
      = f.text_field :q, placeholder: "Buscar...", class: "input-text"
      = f.submit "Buscar", class: "btn-primary"

  -# Contenido principal
  - if @products.any?
    .card
      %table.table
        %thead
          %tr
            %th Código
            %th Nombre
            %th Precio
        %tbody
          - @products.each do |product|
            %tr
              %td= product.code
              %td= product.name
              %td= number_to_currency(product.sale_price)
    
    = paginate @products
  - else
    = render "shared/empty_state", 
            icon: "📦",
            title: "No hay productos"
```

### Form Típico

```haml
-# app/views/web/products/_form.html.haml

= form_with model: @product do |f|
  - if @product.errors.any?
    .alert.alert-error
      %ul
        - @product.errors.full_messages.each do |msg|
          %li= msg

  .form-group
    = f.label :code, "Código", class: "label"
    = f.text_field :code, class: "input-text"
  
  .form-group
    = f.label :name, "Nombre", class: "label"
    = f.text_field :name, class: "input-text"
  
  .form-group
    = f.label :sale_price, "Precio", class: "label"
    = f.number_field :sale_price, step: 0.01, class: "input-text"

  .flex.gap-3
    = link_to "Cancelar", products_path, class: "btn-secondary"
    = f.submit "Guardar", class: "btn-primary"
```

### Componentes Reutilizables

```haml
-# app/views/shared/ui/_badge.html.haml
-# Uso: = render "shared/ui/badge", text: "Activo", variant: "success"

- variant ||= "neutral"
- badge_classes = {
  "success" => "bg-green-100 text-green-800",
  "error" => "bg-red-100 text-red-800",
  "warning" => "bg-yellow-100 text-yellow-800",
  "neutral" => "bg-gray-100 text-gray-800"
}[variant]

%span.inline-flex.px-3.py-1.rounded-full.text-xs.font-medium{class: badge_classes}
  = text
```

```haml
-# app/views/shared/_empty_state.html.haml
-# Uso: = render "shared/empty_state", icon: "📦", title: "Sin datos"

.text-center.py-12
  .text-6xl.mb-4= icon
  %h3.text-xl.font-semibold.text-gray-900= title
  - if local_assigns[:description]
    %p.text-gray-600.mt-2= description
```

---

## 5. STIMULUS - Patrones Básicos

### Search Controller (con debounce)

```javascript
// app/javascript/controllers/search_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input"]
  static values = { url: String }

  search() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => {
      this.performSearch()
    }, 300) // Debounce 300ms
  }

  async performSearch() {
    const query = this.inputTarget.value
    if (query.length < 2) return

    const response = await fetch(`${this.urlValue}?q=${query}`)
    // Procesar respuesta...
  }
}
```

### Modal Controller

```javascript
// app/javascript/controllers/modal_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container"]

  open() {
    this.containerTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
  }

  close() {
    this.containerTarget.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
  }

  closeOnEscape(event) {
    if (event.key === "Escape") this.close()
  }
}
```

---

## 6. TESTS - Ejemplos Mínimos

### Test de Model

```ruby
# spec/models/product_spec.rb
require 'rails_helper'

RSpec.describe Product do
  describe 'validations' do
    it { should validate_presence_of(:code) }
    it { should validate_uniqueness_of(:code) }
  end

  describe '#current_stock' do
    let(:product) { create(:product) }

    it 'calculates stock from all movements' do
      create(:stock_movement, product: product, quantity: 50)
      create(:stock_movement, product: product, quantity: -10)
      
      expect(product.current_stock).to eq(40)
    end
  end
end
```

### Test de Service

```ruby
# spec/services/sales/create_order_spec.rb
require 'rails_helper'

RSpec.describe Sales::CreateOrder do
  let(:customer) { create(:customer) }
  let(:product) { create(:product) }
  let(:user) { create(:user) }
  
  before do
    create(:stock_movement, product: product, quantity: 50)
  end

  describe '#call' do
    it 'creates order successfully' do
      result = described_class.new(
        customer: customer,
        items: [{ product_id: product.id, quantity: 2, unit_price: 100 }],
        order_type: 'credit',
        user: user
      ).call

      expect(result.success?).to be true
      expect(result.record).to be_a(Order)
    end

    it 'reduces product stock' do
      expect {
        described_class.new(
          customer: customer,
          items: [{ product_id: product.id, quantity: 2, unit_price: 100 }],
          order_type: 'credit',
          user: user
        ).call
      }.to change { product.reload.current_stock }.by(-2)
    end

    it 'fails with insufficient stock' do
      result = described_class.new(
        customer: customer,
        items: [{ product_id: product.id, quantity: 100, unit_price: 100 }],
        order_type: 'credit',
        user: user
      ).call

      expect(result.success?).to be false
      expect(result.errors).to include(/Stock insuficiente/)
    end
  end
end
```

---

## 7. ANTI-PATRONES - Evitar

### ❌ NO: Editar stock directamente

```ruby
# MAL - NUNCA hacer esto desde un controller / vista / helper
product.update(current_stock: 50)

# BIEN - Siempre usar un service dedicado de inventario
result = Inventory::AdjustStock.new(
  product: product,
  quantity_diff: 10,
  reason: "Reconteo físico",
  user: current_user
).call
```

### ❌ NO: Lógica de negocio en controller

```ruby
# MAL
def create
  @order = Order.create!(order_params)
  @order.items.each do |item|
    product = item.product
    product.stock -= item.quantity
    product.save!
  end
  redirect_to @order
end
```

### ✅ SÍ: Usar service

```ruby
# BIEN
def create
  result = Sales::CreateOrder.new(...).call
  
  if result.success?
    redirect_to result.record
  else
    render :new
  end
end
```

### ❌ NO: Queries en vistas

```ruby
# MAL
-# En la vista
- Product.where(status: 'active').each do |product|
  = product.name
```

### ✅ SÍ: Queries en controller

```ruby
# BIEN
# En el controller
def index
  @products = Product.active
end

# En la vista
- @products.each do |product|
  = product.name
```

---

## 8. REGLAS CRÍTICAS DE STOCK

### Crear Venta (genera movimientos negativos)

```ruby
# En el service
order.order_items.each do |item|
  StockMovement.create!(
    product: item.product,
    quantity: -item.quantity,  # NEGATIVO
    movement_type: 'sale',
    reference: order
  )
end
```

### Anular Venta (genera movimientos inversos)

```ruby
# En el service
order.order_items.each do |item|
  StockMovement.create!(
    product: item.product,
    quantity: item.quantity,  # POSITIVO (reversa)
    movement_type: 'adjustment',
    reference: order,
    notes: "Anulación de venta ##{order.id}"
  )
end
```

### Crear Compra (genera movimientos positivos)

```ruby
# En el service
purchase.purchase_items.each do |item|
  StockMovement.create!(
    product: item.product,
    quantity: item.quantity,  # POSITIVO
    movement_type: 'purchase',
    reference: purchase
  )
end
```

---

## 9. TAILWIND - Clases Útiles

### Layout y Espaciado

```haml
.container.mx-auto.px-6.py-8          # Container con padding
.grid.grid-cols-1.md:grid-cols-2.gap-6  # Grid responsive
.flex.justify-between.items-center     # Flexbox
.space-y-4                             # Espaciado vertical entre hijos
```

### Componentes Comunes

```haml
-# Botón primario
.btn-primary  # Definir en CSS o usar:
.px-4.py-2.bg-primary.text-white.rounded-lg.hover:bg-primary-dark

-# Card
.card  # O:
.bg-white.border.border-gray-200.rounded-xl.shadow-sm.p-6

-# Input
.input-text  # O:
.w-full.px-3.py-2.border.border-gray-300.rounded-lg.focus:ring-2.focus:ring-primary
```

---

## 10. RECORDATORIOS FINALES

### Siempre Hacer:
- ✅ Services para operaciones complejas
- ✅ Validar stock ANTES de crear ventas
- ✅ Usar transacciones en services
- ✅ Devolver Result desde services
- ✅ Controllers delgados
- ✅ Manejar stock SIEMPRE a través de StockMovement y/o services de inventario

### Nunca Hacer:
- ❌ Lógica de negocio en controllers
- ❌ Lógica de negocio en vistas
- ❌ Editar `current_stock` directamente desde controllers, helpers o vistas
- ❌ Crear/actualizar StockMovement "a mano" fuera de los services de inventario

---

**Para más detalles:** Consultar `DEVELOPMENT_GUIDE.md`