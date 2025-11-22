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
    # Método de clase que instancia y ejecuta
    def self.call(customer:, items:, order_type:, user:)
      new(customer: customer, items: items, order_type: order_type, user: user).call
    end

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
  result = Sales::CreateOrder.call(
    customer: @customer,
    items: parse_items,
    order_type: params[:order_type],
    user: current_user
  )

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
  has_many :purchase_items
  belongs_to :category, optional: true

  # Validaciones
  validates :sku, presence: true, uniqueness: true
  validates :name, presence: true
  validates :price_unit, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :cost_unit, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :cost_currency, inclusion: { in: %w[USD ARS] }
  validates :origin, inclusion: { in: ORIGINS, allow_blank: true }
  validates :product_type, inclusion: { in: %w[oem aftermarket], allow_blank: true }

  # Scopes útiles
  scope :active, -> { where(active: true) }
  scope :with_low_stock, -> { where('current_stock < ?', 5) }
  scope :by_origin, ->(origin) { where(origin: origin) if origin.present? }
  scope :oem, -> { where(product_type: 'oem') }
  scope :aftermarket, -> { where(product_type: 'aftermarket') }
  scope :search, ->(query) {
    where('sku ILIKE ? OR name ILIKE ? OR brand ILIKE ?', 
          "%#{query}%", "%#{query}%", "%#{query}%") if query.present?
  }

  # Stock cacheado:
  # - current_stock es una columna en products
  # - Se actualiza automáticamente cuando se crean/destruyen StockMovements
  # - NUNCA editar directamente desde controllers o vistas
  
  # Costo promedio ponderado:
  # - cost_unit representa el costo promedio de TODAS las compras confirmadas
  # - Se recalcula con recalculate_average_cost! al confirmar/anular compras
  def recalculate_average_cost!
    purchase_items = PurchaseItem.joins(:purchase)
                                  .where(product: self)
                                  .where(purchases: { status: 'confirmed' })
    
    return if purchase_items.empty?
    
    total_cost_usd = 0.0
    total_quantity = 0
    
    purchase_items.find_each do |item|
      if item.purchase.currency == 'USD'
        total_cost_usd += item.unit_cost * item.quantity
      else
        cost_in_usd = item.unit_cost / (item.purchase.exchange_rate || 1200)
        total_cost_usd += cost_in_usd * item.quantity
      end
      
      total_quantity += item.quantity
    end
    
    if total_quantity > 0
      average_cost = (total_cost_usd / total_quantity).round(2)
      update_columns(cost_unit: average_cost, cost_currency: 'USD')
    end
  end
  
  alias_method :average_cost, :cost_unit

  def low_stock?
    current_stock.to_i < 5
  end
  
  def margin(exchange_rate = nil)
    return 0 if price_unit.nil?
    price_unit - cost_in_ars(exchange_rate)
  end
  
  def cost_in_ars(exchange_rate = nil)
    return 0 if cost_unit.nil?
    return cost_unit if cost_currency == 'ARS'
    
    rate = exchange_rate || 1000
    cost_unit * rate
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
                          .where(order_type: 'credit')
                          .where.not(status: 'cancelled')
                          .sum(:total_amount)
    
    total_payments = payments.sum(:amount)
    
    total_credit_sales - total_payments
  end
end
```

### Reference Polimórfico en StockMovement

```ruby
class StockMovement < ApplicationRecord
  belongs_to :product
  belongs_to :stock_location
  belongs_to :reference, polymorphic: true, optional: true
  
  # reference puede ser Order, Purchase, o nil (ajustes manuales)
  # reference_type + reference_id se guardan automáticamente
end

class Order < ApplicationRecord
  has_many :stock_movements, as: :reference
end

class Purchase < ApplicationRecord
  has_many :stock_movements, as: :reference
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
    params.require(:product).permit(:sku, :name, :price_unit, :cost_unit, :cost_currency)
  end
end
```

### Controller con Service

```ruby
class OrdersController < ApplicationController
  def create
    result = Sales::CreateOrder.call(
      customer: find_customer,
      items: parse_items,
      order_type: order_params[:order_type],
      user: current_user
    )

    if result.success?
      redirect_to result.record, notice: "Venta registrada"
    else
      flash.now[:alert] = result.errors.join(", ")
      render :new, status: :unprocessable_entity
    end
  end
end

class PurchasesController < ApplicationController
  def create
    result = Purchasing::CreatePurchase.call(
      supplier: @supplier,
      items: parse_items,
      currency: params[:currency],
      exchange_rate: params[:exchange_rate]
    )

    if result.success?
      redirect_to result.record, notice: "Compra registrada"
    else
      flash.now[:alert] = result.errors.join(", ")
      render :new, status: :unprocessable_entity
    end
  end
end

class PaymentsController < ApplicationController
  def create
    result = Payments::RegisterPayment.call(
      customer: @customer,
      amount: params[:amount],
      payment_method: params[:payment_method]
    )

    if result.success?
      redirect_to @customer, notice: "Pago registrado"
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
            %th SKU
            %th Nombre
            %th Precio
            %th Stock
        %tbody
          - @products.each do |product|
            %tr
              %td= product.sku
              %td= product.name
              %td= number_to_currency(product.price_unit)
              %td= product.current_stock
    
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
    = f.label :sku, "SKU", class: "label"
    = f.text_field :sku, class: "input-text"
  
  .form-group
    = f.label :name, "Nombre", class: "label"
    = f.text_field :name, class: "input-text"
  
  .form-group
    = f.label :price_unit, "Precio", class: "label"
    = f.number_field :price_unit, step: 0.01, class: "input-text"

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
    it { should validate_presence_of(:sku) }
    it { should validate_uniqueness_of(:sku) }
  end

  describe '#recalculate_average_cost!' do
    let(:product) { create(:product) }
    let(:supplier) { create(:supplier) }

    it 'calculates weighted average from multiple purchases' do
      purchase1 = create(:purchase, supplier: supplier, currency: 'USD')
      create(:purchase_item, purchase: purchase1, product: product, quantity: 5, unit_cost: 10)
      
      purchase2 = create(:purchase, supplier: supplier, currency: 'USD')
      create(:purchase_item, purchase: purchase2, product: product, quantity: 5, unit_cost: 20)
      
      product.recalculate_average_cost!
      
      # (5×10 + 5×20) / 10 = 15
      expect(product.cost_unit).to eq(15.0)
    end
  end
end
```

### Test de Service

```ruby
# spec/services/sales/create_order_spec.rb
require 'rails_helper'

RSpec.describe Sales::CreateOrder do
  let(:customer) { create(:customer, has_credit_account: true) }
  let(:product) { create(:product, current_stock: 50) }
  let!(:stock_location) { create(:stock_location) }
  
  describe '.call' do
    it 'creates order successfully' do
      result = described_class.call(
        customer: customer,
        items: [{ product_id: product.id, quantity: 2, unit_price: 100 }],
        order_type: 'credit'
      )

      expect(result.success?).to be true
      expect(result.record).to be_a(Order)
    end

    it 'reduces product stock' do
      expect {
        described_class.call(
          customer: customer,
          items: [{ product_id: product.id, quantity: 2, unit_price: 100 }],
          order_type: 'credit'
        )
      }.to change { product.reload.current_stock }.by(-2)
    end

    it 'fails with insufficient stock' do
      result = described_class.call(
        customer: customer,
        items: [{ product_id: product.id, quantity: 100, unit_price: 100 }],
        order_type: 'credit'
      )

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
# MAL - NUNCA hacer esto
product.update(current_stock: 50)

# BIEN - Usar service de inventario
result = Inventory::AdjustStock.call(
  product: product,
  stock_location: stock_location,
  movement_type: :adjustment,
  quantity: 10,
  note: "Reconteo físico"
)
```

### ❌ NO: Lógica de negocio en controller

```ruby
# MAL
def create
  @order = Order.create!(order_params)
  @order.items.each do |item|
    product = item.product
    product.current_stock -= item.quantity
    product.save!
  end
  redirect_to @order
end
```

### ✅ SÍ: Usar service

```ruby
# BIEN
def create
  result = Sales::CreateOrder.call(
    customer: @customer,
    items: parse_items,
    order_type: params[:order_type]
  )
  
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
- Product.where(active: true).each do |product|
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

## 8. REGLAS CRÍTICAS DE STOCK Y COSTOS

### Crear Venta (genera movimientos negativos)

```ruby
# En el service Sales::CreateOrder
result = Inventory::AdjustStock.call(
  product: product,
  stock_location: stock_location,
  movement_type: 'sale',
  quantity: -item.quantity,  # NEGATIVO
  reference: @order  # Polimórfico
)
```

### Anular Venta (genera movimientos inversos)

```ruby
# En el service Sales::CancelOrder
result = Inventory::AdjustStock.call(
  product: product,
  stock_location: stock_location,
  movement_type: 'adjustment',
  quantity: item.quantity,  # POSITIVO (reversa)
  reference: @order,
  note: "Anulación de venta ##{@order.id}"
)
```

### Crear Compra (genera movimientos positivos + actualiza costo)

```ruby
# En el service Purchasing::CreatePurchase
# 1. Crear movimientos de stock
result = Inventory::AdjustStock.call(
  product: product,
  stock_location: stock_location,
  movement_type: 'purchase',
  quantity: item.quantity,  # POSITIVO
  reference: @purchase
)

# 2. Recalcular costo promedio
product.recalculate_average_cost!
```

### Anular Compra (reversa movimientos + recalcula costo)

```ruby
# En el service Purchasing::CancelPurchase
# 1. Revertir stock
result = Inventory::AdjustStock.call(
  product: product,
  stock_location: stock_location,
  movement_type: 'adjustment',
  quantity: -item.quantity,  # NEGATIVO (reversa)
  reference: @purchase
)

# 2. Recalcular costo promedio (sin la compra cancelada)
product.recalculate_average_cost!
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
.px-4.py-2.bg-teal-600.text-white.rounded-lg.hover:bg-teal-700

-# Card
.card  # O:
.bg-white.border.border-gray-200.rounded-xl.shadow-sm.p-6

-# Input
.input-text  # O:
.w-full.px-3.py-2.border.border-gray-300.rounded-lg.focus:ring-2.focus:ring-teal-500
```

---

## 10. RECORDATORIOS FINALES

### Siempre Hacer:
- ✅ Services para operaciones complejas (ventas, compras, pagos)
- ✅ Método de clase `.call` en todos los services
- ✅ Validar stock ANTES de crear ventas
- ✅ Usar transacciones en services
- ✅ Devolver Result desde services
- ✅ Controllers delgados (solo llaman services)
- ✅ Stock SIEMPRE vía Inventory::AdjustStock
- ✅ Recalcular costo promedio al confirmar/anular compras
- ✅ Reference polimórfico para trazabilidad

### Nunca Hacer:
- ❌ Lógica de negocio en controllers
- ❌ Lógica de negocio en vistas
- ❌ Editar `current_stock` directamente
- ❌ Editar `cost_unit` manualmente (usar recalculate_average_cost!)
- ❌ Crear StockMovement fuera de Inventory::AdjustStock
- ❌ Olvidar validar stock antes de vender
- ❌ Olvidar transacciones en operaciones multi-modelo
- ❌ Usar `.new().call` en vez de `.call()` en services

---

**Para más detalles:** Consultar `DEVELOPMENT_GUIDE.md` y `FLUJOS.md`