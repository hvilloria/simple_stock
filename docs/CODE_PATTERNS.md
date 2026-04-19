# CODE_PATTERNS.md

## Purpose

This document provides practical implementation patterns used in this project.

It answers:

> “What should code look like here?”

It does NOT define architecture or policy.  
That belongs to `docs/DEVELOPMENT_GUIDE.md`.

---

## General Rule

If unsure:

1. Check the real code first
2. Find the closest existing pattern
3. Reuse the structure
4. Adapt only what is necessary

Prefer consistency over cleverness.

---

## Result Object

Use this pattern for service objects that coordinate business logic.

```ruby
Result = Struct.new(:success?, :record, :errors, keyword_init: true) do
  def failure?
    !success?
  end
end
```

---

## Controller Patterns

### 1. Simple CRUD Controller

Use direct ActiveRecord when the action is simple and does not require orchestration.

```ruby
module Web
  class SuppliersController < ApplicationController
    before_action :set_supplier, only: %i[show edit update destroy]

    def create
      @supplier = Supplier.new(supplier_params)
      authorize @supplier

      if @supplier.save
        redirect_to web_supplier_path(@supplier), notice: "Supplier created successfully."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      authorize @supplier

      if @supplier.update(supplier_params)
        redirect_to web_supplier_path(@supplier), notice: "Supplier updated successfully."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_supplier
      @supplier = Supplier.find(params[:id])
    end

    def supplier_params
      params.require(:supplier).permit(:name, :email, :phone)
    end
  end
end
```

### 2. Service-Backed Controller

Use a service when the action affects multiple models, coordinates stock, or requires transactions.

```ruby
module Web
  class OrdersController < ApplicationController
    def create
      result = Sales::CreateOrder.call(
        customer: resolved_customer,
        items: parsed_items,
        order_type: order_params[:order_type],
        user: current_user
      )

      if result.success?
        redirect_to web_order_path(result.record), notice: "Order created successfully."
      else
        flash.now[:alert] = result.errors.join(", ")
        render :new, status: :unprocessable_entity
      end
    end

    private

    def order_params
      params.require(:order).permit(:customer_id, :order_type, :channel)
    end
  end
end
```

### 3. Authorization Pattern

Authorize at controller level unless there is a strong reason not to.

```ruby
def show
  @product = Product.find(params[:id])
  authorize @product
end
```

For collections:

```ruby
def index
  @products = policy_scope(Product).order(:name)
end
```

---

## Service Patterns

### 1. Standard Service Structure

Use for multi-step business logic.

```ruby
module Sales
  class CreateOrder
    def self.call(**params)
      new(**params).call
    end

    def initialize(customer:, items:, order_type:, user:)
      @customer = customer
      @items = items
      @order_type = order_type
      @user = user
    end

    def call
      validate!

      ActiveRecord::Base.transaction do
        create_order
        create_items
        create_stock_movements

        Result.new(success?: true, record: @order, errors: [])
      end
    rescue ValidationError => e
      Result.new(success?: false, record: nil, errors: [e.message])
    rescue StandardError => e
      Rails.logger.error("[Sales::CreateOrder] #{e.message}")
      Result.new(success?: false, record: nil, errors: ["Unexpected error"])
    end

    private

    class ValidationError < StandardError; end

    def validate!
      raise ValidationError, "Items cannot be blank" if @items.blank?
    end

    def create_order
      @order = Order.create!(
        customer: @customer,
        order_type: @order_type,
        user: @user,
        status: "confirmed"
      )
    end

    def create_items
      @items.each do |item|
        @order.order_items.create!(item)
      end
    end

    def create_stock_movements
      @order.order_items.each do |item|
        Inventory::AdjustStock.call(
          product: item.product,
          quantity: -item.quantity,
          movement_type: "sale",
          reference: @order
        )
      end
    end
  end
end
```

### 2. Validation Error Pattern

Use a small internal exception when validation should stop the service cleanly.

```ruby
class ValidationError < StandardError; end
```

### 3. Service Boundary Rule

Use services when:
- more than one model is involved
- stock is affected
- a transaction is needed
- business rules span multiple steps

Do NOT create a service for trivial CRUD.

---

## Query Object Pattern

Use query objects for read-heavy reporting logic.

```ruby
module SalesLedger
  module Reports
    class SummaryQuery
      def self.call(relation: SalesLedgerEntry.all, filters: {})
        new(relation: relation, filters: filters).call
      end

      def initialize(relation:, filters:)
        @relation = relation
        @filters = filters
      end

      def call
        scoped_relation
          .group(:sale_date)
          .select("sale_date, COUNT(*) AS rows_count, SUM(total_amount) AS total_amount")
          .order(sale_date: :desc)
      end

      private

      def scoped_relation
        scope = @relation
        scope = scope.where(seller_name: @filters[:seller_name]) if @filters[:seller_name].present?
        scope
      end
    end
  end
end
```

Use query objects for reporting and filtering.  
Do NOT put reporting SQL in controllers.

---

## Model Patterns

### 1. Model Responsibilities

Models should contain:
- associations
- validations
- scopes
- simple calculations
- small domain helpers

```ruby
class Product < ApplicationRecord
  has_many :stock_movements, dependent: :restrict_with_exception

  validates :sku, presence: true, uniqueness: true
  validates :name, presence: true

  scope :active, -> { where(active: true) }
  scope :search, ->(query) {
    return all if query.blank?

    where("sku ILIKE :q OR name ILIKE :q", q: "%#{query}%")
  }

  def low_stock?
    current_stock.to_i < 5
  end
end
```

### 2. What NOT to Put in Models

Do NOT put:
- multi-step orchestration
- stock mutation workflows
- controller-like parameter handling
- large reporting queries

---

## Stock Patterns

### Preferred Pattern

Stock changes should go through the stock workflow, not direct updates.

```ruby
Inventory::AdjustStock.call(
  product: product,
  quantity: -3,
  movement_type: "sale",
  reference: order
)
```

### Low-Level Movement Pattern

Only use this directly if you are already inside the correct lower-level stock workflow.

```ruby
StockMovement.create!(
  product: product,
  stock_location: StockLocation.first!,
  quantity: -3,
  movement_type: "sale",
  reference: order
)
```

### Forbidden

```ruby
product.update!(current_stock: 10)
```

---

## View Patterns (HAML)

### 1. Basic Index Pattern

```haml
- content_for :page_title, "Products"

.card
  .card-header
    %h1 Products

  .card-body
    - if @products.any?
      %table
        %thead
          %tr
            %th SKU
            %th Name
        %tbody
          - @products.each do |product|
            %tr
              %td= product.sku
              %td= product.name
    - else
      %p No products found.
```

### 2. Form Pattern

```haml
= form_with model: [:web, @supplier] do |f|
  - if @supplier.errors.any?
    .alert.alert-error
      %ul
        - @supplier.errors.full_messages.each do |message|
          %li= message

  .form-group
    = f.label :name
    = f.text_field :name, class: "input-modern"

  .form-actions
    = f.submit "Save", class: "btn-primary"
```

### View Rules

Views should:
- render data
- use partials when repetition appears
- stay presentation-focused

Views should NOT:
- query the database
- contain business logic
- calculate complex totals inline

---

## Stimulus Pattern

Use Stimulus for small UI behaviors.

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input"]

  connect() {
    // initialize behavior
  }

  clear() {
    this.inputTarget.value = ""
  }
}
```

Keep controllers small and focused.

---

## Testing Patterns

### 1. Service Spec

```ruby
RSpec.describe Sales::CreateOrder do
  describe ".call" do
    it "creates the order and returns success" do
      result = described_class.call(
        customer: customer,
        items: items,
        order_type: "cash",
        user: user
      )

      expect(result.success?).to be true
      expect(result.record).to be_present
      expect(result.errors).to eq([])
    end
  end
end
```

### 2. Request Spec

```ruby
RSpec.describe "Web::Suppliers", type: :request do
  describe "POST /web/suppliers" do
    it "creates a supplier" do
      post web_suppliers_path, params: {
        supplier: { name: "ACME" }
      }

      expect(response).to redirect_to(web_supplier_path(Supplier.last))
    end
  end
end
```

### Testing Rule

Prefer tests for:
- services
- critical business rules
- request flows with meaningful behavior

Do not over-test trivial markup-only views.

---

## Anti-Patterns

### Fat Controller

```ruby
def create
  order = Order.create!(...)
  order.order_items.create!(...)
  StockMovement.create!(...)
end
```

### Trivial CRUD Wrapped in a Service

```ruby
class CreateSupplier
  def call
    Supplier.create!(...)
  end
end
```

### Business Logic in the View

```haml
- total = @orders.select { |o| o.status == "confirmed" }.sum(&:total_amount)
%p= total
```

### God Service

```ruby
class ProcessEverything
  def call
    # orders, stock, payments, invoices, notifications, reports...
  end
end
```

### Direct Stock Update

```ruby
product.update!(current_stock: 999)
```

---

## Final Rule

If unsure:
- find the closest real example in the codebase
- copy the structure
- adapt it carefully
- do not reinvent the pattern
