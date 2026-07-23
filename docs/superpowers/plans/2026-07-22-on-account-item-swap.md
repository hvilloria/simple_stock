# Swap Products on Payments on Account — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let vendedor/admin replace the product and/or quantity of any undelivered line on an `on_account` order, recalculating the order totals.

**Architecture:** New `Sales::ReplaceOrderItem` service (Result pattern, delta-based total update), one new policy method, a nested `items` controller with edit/update, a new edit view with a glue Stimulus controller reusing the existing `product-search` component, and a row-actions column on the payments-on-account show view.

**Tech Stack:** Rails 7.2, HAML, TailwindCSS (slate palette), Stimulus, Pundit, RSpec + FactoryBot.

**Spec:** `docs/superpowers/specs/2026-07-22-on-account-item-swap-design.md` — read it before starting.

## Global Constraints

- **NO git commits during implementation.** Project rule: one commit per feature, made by the user at the end. Never run `git commit`. The final task stages files and hands over the message (scope `feat_22`, English only, no attribution lines).
- Views are HAML only. UI follows `docs/UI_DESIGN_SPEC.md`: slate palette, sober, no saturated accents.
- Services return `Result` (`app/services/result.rb`): `Result.new(success?:, record:, errors:)`.
- Controllers stay thin: params → service → redirect.
- Code comments: English, minimal — only where genuinely needed. No references to AGENTS.md or other doctrine docs.
- Use `Date.current` / `Time.current`, never `Date.today` / `Time.now`.
- Do not touch `products.current_stock` or create `StockMovement`s — this feature has no inventory side effects.
- The delta-based total update is mandatory — never call `Order#calculate_total!` (it would wipe effective discounts already subtracted from `total_amount` by `Payments::CollectOnAccount`).

---

### Task 1: Policy — `PaymentOnAccountPolicy#edit_item?`

**Files:**
- Modify: `app/policies/payment_on_account_policy.rb`
- Test: `spec/policies/payment_on_account_policy_spec.rb`

**Interfaces:**
- Produces: `PaymentOnAccountPolicy#edit_item?` → true for vendedor/admin on a non-cancelled `on_account` order. Used by Task 3 (controller authorize) and Task 5 (show view gating).

- [ ] **Step 1: Write the failing tests**

Add to each existing role context in `spec/policies/payment_on_account_policy_spec.rb` (inside `context "vendedor"`, `context "caja"`, `context "admin"` respectively):

```ruby
# inside context "vendedor"
it "permits edit_item" do
  expect(subject.edit_item?).to be true
end

it "forbids edit_item on a cancelled order" do
  cancelled = build(:order, :on_account, :cancelled)
  expect(described_class.new(user, cancelled).edit_item?).to be false
end

# inside context "caja"
it "forbids edit_item" do
  expect(subject.edit_item?).to be false
end

# inside context "admin"
it "permits edit_item" do
  expect(subject.edit_item?).to be true
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/policies/payment_on_account_policy_spec.rb`
Expected: 4 failures with `NoMethodError: undefined method 'edit_item?'`

- [ ] **Step 3: Implement the policy method**

In `app/policies/payment_on_account_policy.rb`, after `deliver?`:

```ruby
def edit_item?
  (user.vendedor? || user.admin?) && record.on_account_order_type? &&
    !record.cancelled_status?
end
```

- [ ] **Step 4: Run to verify pass**

Run: `bundle exec rspec spec/policies/payment_on_account_policy_spec.rb`
Expected: all green.

---

### Task 2: Service — `Sales::ReplaceOrderItem`

**Files:**
- Create: `app/services/sales/replace_order_item.rb`
- Test: `spec/services/sales/replace_order_item_spec.rb`

**Interfaces:**
- Consumes: `Result` struct, `Order#refresh_status_from_balance!`, `Product.active` scope.
- Produces: `Sales::ReplaceOrderItem.call(order_item:, product_id:, quantity:)` → `Result` (`record` = the updated `OrderItem` on success). Used by Task 3.

**Behavior contract (from the spec):**
- Price resolution: product changed → new product's `price_unit`; product unchanged → keep the line's `unit_price`.
- `delta = (new_qty × new_price) − (old_qty × old_price)`, applied to BOTH `total_amount` and `original_total_amount`.
- No overpayment guard: a swap below the collected amount is allowed (known gap).

- [ ] **Step 1: Write the failing spec**

Create `spec/services/sales/replace_order_item_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Sales::ReplaceOrderItem do
  let(:order) { create(:order, :on_account, total_amount: 1000, original_total_amount: 1000) }
  let(:old_product) { create(:product, price_unit: 500) }
  let(:new_product) { create(:product, price_unit: 300) }
  let!(:item) { create(:order_item, order: order, product: old_product, quantity: 2, unit_price: 500) }

  it "swaps the product at catalog price and applies the delta to both totals" do
    result = described_class.call(order_item: item, product_id: new_product.id, quantity: 2)

    expect(result).to be_success
    item.reload
    expect(item.product).to eq(new_product)
    expect(item.unit_price).to eq(300)
    expect(item.quantity).to eq(2)
    # delta = (2*300) - (2*500) = -400
    expect(order.reload.total_amount).to eq(600)
    expect(order.original_total_amount).to eq(600)
  end

  it "keeps the original line price on a quantity-only edit" do
    catalog_moved = item.product
    catalog_moved.update!(price_unit: 999)

    result = described_class.call(order_item: item, product_id: catalog_moved.id, quantity: 3)

    expect(result).to be_success
    item.reload
    expect(item.unit_price).to eq(500) # NOT 999
    expect(item.quantity).to eq(3)
    # delta = (3*500) - (2*500) = 500
    expect(order.reload.total_amount).to eq(1500)
    expect(order.original_total_amount).to eq(1500)
  end

  it "preserves the original-minus-total gap left by discounted collections" do
    # Simulate a prior discounted collection: total lowered, original untouched
    order.update!(total_amount: 900)

    described_class.call(order_item: item, product_id: new_product.id, quantity: 2)

    order.reload
    # gap (original - total) must stay 100
    expect(order.original_total_amount - order.total_amount).to eq(100)
  end

  it "reopens a confirmed order when the swap makes it owe money again" do
    create(:payment_allocation, order: order,
           payment: create(:payment, customer: order.customer, amount: 1000), amount: 1000)
    order.refresh_status_from_balance!
    expect(order.reload.status).to eq("confirmed")

    pricier = create(:product, price_unit: 800)
    described_class.call(order_item: item, product_id: pricier.id, quantity: 2)

    expect(order.reload.status).to eq("pending")
  end

  it "rejects an already delivered item" do
    item.update!(delivered_at: Time.current)
    result = described_class.call(order_item: item, product_id: new_product.id, quantity: 2)

    expect(result).to be_failure
    expect(result.errors).to include("El producto ya fue entregado")
    expect(item.reload.product).to eq(old_product)
  end

  it "rejects a non on_account order" do
    immediate = create(:order, order_type: "immediate", total_amount: 100, original_total_amount: 100)
    other_item = create(:order_item, order: immediate, product: old_product, quantity: 1, unit_price: 100)

    result = described_class.call(order_item: other_item, product_id: new_product.id, quantity: 1)
    expect(result).to be_failure
  end

  it "rejects a cancelled order" do
    order.update!(status: "cancelled")
    result = described_class.call(order_item: item, product_id: new_product.id, quantity: 2)
    expect(result).to be_failure
  end

  it "rejects quantity below 1" do
    result = described_class.call(order_item: item, product_id: new_product.id, quantity: 0)
    expect(result).to be_failure
    expect(result.errors).to include("La cantidad debe ser mayor a cero")
  end

  it "rejects an unknown product" do
    result = described_class.call(order_item: item, product_id: -1, quantity: 2)
    expect(result).to be_failure
    expect(result.errors).to include("Producto inválido")
  end

  it "rejects an inactive product" do
    inactive = create(:product, :inactive, price_unit: 300)
    result = described_class.call(order_item: item, product_id: inactive.id, quantity: 2)
    expect(result).to be_failure
  end

  it "rejects a soft-deleted product" do
    deleted = create(:product, price_unit: 300)
    deleted.destroy
    result = described_class.call(order_item: item, product_id: deleted.id, quantity: 2)
    expect(result).to be_failure
  end

  it "rejects a product without catalog price" do
    no_price = create(:product, price_unit: 0)
    result = described_class.call(order_item: item, product_id: no_price.id, quantity: 2)

    expect(result).to be_failure
    expect(result.errors).to include("El producto no tiene precio de catálogo — cargalo en Productos")
  end

  it "allows a swap that leaves the total below the collected amount (known gap)" do
    create(:payment_allocation, order: order,
           payment: create(:payment, customer: order.customer, amount: 800), amount: 800)

    cheap = create(:product, price_unit: 100)
    result = described_class.call(order_item: item, product_id: cheap.id, quantity: 2)

    expect(result).to be_success
    order.reload
    expect(order.total_amount).to eq(200)
    expect(order.outstanding_balance).to eq(-600)
    expect(order.status).to eq("confirmed")
  end

  it "does not create a StockMovement" do
    expect {
      described_class.call(order_item: item, product_id: new_product.id, quantity: 2)
    }.not_to change(StockMovement, :count)
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/services/sales/replace_order_item_spec.rb`
Expected: FAIL with `NameError: uninitialized constant Sales::ReplaceOrderItem`

- [ ] **Step 3: Implement the service**

Create `app/services/sales/replace_order_item.rb`:

```ruby
# frozen_string_literal: true

module Sales
  # Replaces the product and/or quantity of an undelivered line on an
  # on_account order. When the product changes, the line takes the catalog
  # price; a quantity-only edit keeps the original line price.
  class ReplaceOrderItem
    def self.call(order_item:, product_id:, quantity:)
      new(order_item: order_item, product_id: product_id, quantity: quantity).call
    end

    def initialize(order_item:, product_id:, quantity:)
      @order_item = order_item
      @order      = order_item.order
      @product_id = product_id.to_i
      @quantity   = quantity.to_i
    end

    def call
      validate!

      ActiveRecord::Base.transaction do
        old_subtotal = @order_item.quantity * @order_item.unit_price
        new_price    = product_changed? ? new_product.price_unit : @order_item.unit_price
        delta        = (@quantity * new_price) - old_subtotal

        @order_item.update!(product_id: @product_id, quantity: @quantity, unit_price: new_price)
        # Delta on BOTH totals: re-summing items would wipe the effective
        # discounts already subtracted from total_amount by CollectOnAccount.
        @order.update!(
          total_amount:          @order.total_amount + delta,
          original_total_amount: @order.original_total_amount + delta
        )
        @order.refresh_status_from_balance!
      end

      Result.new(success?: true, record: @order_item, errors: [])
    rescue ValidationError => e
      Result.new(success?: false, record: nil, errors: [ e.message ])
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, record: nil, errors: e.record.errors.full_messages)
    rescue StandardError => e
      Rails.logger.error("Error in Sales::ReplaceOrderItem: #{e.message}")
      Result.new(success?: false, record: nil, errors: [ "Error actualizando el producto" ])
    end

    private

    class ValidationError < StandardError; end

    def validate!
      unless @order.on_account_order_type? && !@order.cancelled_status?
        raise ValidationError, "La operación no es un pago a cuenta activo"
      end

      raise ValidationError, "El producto ya fue entregado" if @order_item.delivered_at.present?
      raise ValidationError, "La cantidad debe ser mayor a cero" if @quantity <= 0

      return unless product_changed?

      raise ValidationError, "Producto inválido" if new_product.nil?
      unless new_product.price_unit.to_d.positive?
        raise ValidationError, "El producto no tiene precio de catálogo — cargalo en Productos"
      end
    end

    def product_changed?
      @product_id != @order_item.product_id
    end

    def new_product
      @new_product ||= Product.active.find_by(id: @product_id)
    end
  end
end
```

- [ ] **Step 4: Run to verify pass**

Run: `bundle exec rspec spec/services/sales/replace_order_item_spec.rb`
Expected: all green.

---

### Task 3: Routes + `Web::PaymentsOnAccount::ItemsController`

**Files:**
- Modify: `config/routes.rb` (the `resources :payments_on_account` block, around line 45)
- Create: `app/controllers/web/payments_on_account/items_controller.rb`
- Test: `spec/requests/web/payments_on_account/items_spec.rb`

**Interfaces:**
- Consumes: `Sales::ReplaceOrderItem.call(order_item:, product_id:, quantity:)` (Task 2), `PaymentOnAccountPolicy#edit_item?` (Task 1).
- Produces: path helpers `edit_web_payments_on_account_item_path(order, item)` (GET) and `web_payments_on_account_item_path(order, item)` (PATCH). Used by Tasks 4 and 5. Instance vars for the view: `@order`, `@item`.

- [ ] **Step 1: Write the failing request spec**

Create `spec/requests/web/payments_on_account/items_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Web::PaymentsOnAccount::Items", type: :request do
  let(:vendedor) { create(:user, role: "vendedor") }
  let(:caja) { create(:user, role: "caja") }
  let(:old_product) { create(:product, name: "Bomba importada", price_unit: 500) }
  let(:new_product) { create(:product, name: "Bomba local", price_unit: 300) }
  let(:order) { create(:order, :on_account, total_amount: 1000, original_total_amount: 1000) }
  let!(:item) { create(:order_item, order: order, product: old_product, quantity: 2, unit_price: 500) }

  describe "GET edit" do
    it "renders for a vendedor" do
      sign_in vendedor
      get edit_web_payments_on_account_item_path(order, item)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Cambiar producto")
      expect(response.body).to include("Bomba importada")
    end

    it "redirects caja away" do
      sign_in caja
      get edit_web_payments_on_account_item_path(order, item)
      expect(response).to have_http_status(:redirect)
    end

    it "redirects to the show when the item is already delivered" do
      item.update!(delivered_at: Time.current)
      sign_in vendedor
      get edit_web_payments_on_account_item_path(order, item)

      expect(response).to redirect_to(web_payments_on_account_path(order))
      expect(flash[:alert]).to eq("El producto ya fue entregado")
    end
  end

  describe "PATCH update" do
    it "swaps the product and redirects to the show" do
      sign_in vendedor
      patch web_payments_on_account_item_path(order, item),
            params: { product_id: new_product.id, quantity: 2 }

      expect(response).to redirect_to(web_payments_on_account_path(order))
      item.reload
      expect(item.product).to eq(new_product)
      expect(item.unit_price).to eq(300)
      expect(order.reload.total_amount).to eq(600)
    end

    it "redirects back to edit with an alert on failure" do
      item.update!(delivered_at: Time.current)
      sign_in vendedor
      patch web_payments_on_account_item_path(order, item),
            params: { product_id: new_product.id, quantity: 2 }

      expect(response).to redirect_to(edit_web_payments_on_account_item_path(order, item))
      expect(flash[:alert]).to include("El producto ya fue entregado")
    end

    it "forbids caja" do
      sign_in caja
      patch web_payments_on_account_item_path(order, item),
            params: { product_id: new_product.id, quantity: 2 }

      expect(item.reload.product).to eq(old_product)
    end
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/requests/web/payments_on_account/items_spec.rb`
Expected: FAIL with `NameError: undefined ... edit_web_payments_on_account_item_path` (route missing).

- [ ] **Step 3: Add the nested route**

In `config/routes.rb`, inside the existing `resources :payments_on_account` block (keep `resource :payment` and `member { post :deliver }` as they are):

```ruby
resources :payments_on_account, only: [ :index, :show ] do
  resource :payment, only: [ :new, :create ],
                     controller: "payments_on_account/payments"
  resources :items, only: [ :edit, :update ],
                    controller: "payments_on_account/items"
  member do
    post :deliver
  end
end
```

- [ ] **Step 4: Implement the controller**

Create `app/controllers/web/payments_on_account/items_controller.rb`:

```ruby
module Web
  module PaymentsOnAccount
    class ItemsController < ApplicationController
      before_action :set_order_and_item

      def edit
        authorize @order, :edit_item?, policy_class: PaymentOnAccountPolicy

        if @item.delivered_at.present?
          redirect_to web_payments_on_account_path(@order), alert: "El producto ya fue entregado"
        end
      end

      def update
        authorize @order, :edit_item?, policy_class: PaymentOnAccountPolicy

        result = ::Sales::ReplaceOrderItem.call(
          order_item: @item,
          product_id: params[:product_id],
          quantity:   params[:quantity]
        )

        if result.success?
          redirect_to web_payments_on_account_path(@order), notice: "Producto actualizado"
        else
          redirect_to edit_web_payments_on_account_item_path(@order, @item),
                      alert: result.errors.join(", ")
        end
      end

      private

      def set_order_and_item
        @order = Order.on_account.find(params[:payments_on_account_id])
        @item  = @order.order_items.find(params[:id])
      end
    end
  end
end
```

- [ ] **Step 5: Run to verify (view still missing)**

Run: `bundle exec rspec spec/requests/web/payments_on_account/items_spec.rb`
Expected: PATCH examples pass; GET edit examples fail with `ActionView::MissingTemplate` — that is Task 4's job. The delivered-item GET example (redirect) already passes.

---

### Task 4: Edit view + `item_swap` Stimulus controller

**Files:**
- Create: `app/views/web/payments_on_account/items/edit.html.haml`
- Create: `app/javascript/controllers/item_swap_controller.js`
- Test: `spec/requests/web/payments_on_account/items_spec.rb` (Task 3's GET examples turn green)

**Interfaces:**
- Consumes: `@order`, `@item` from Task 3; `product-search` Stimulus component (`product-selected` event with `event.detail.product` = `{id, sku, name, price_unit, ...}` from `Web::ProductsController#search`); path helpers from Task 3.
- Produces: form POSTing `product_id` + `quantity` via PATCH.

**Stimulus notes (patterns to follow):**
- `eagerLoadControllersFrom("controllers", application)` auto-registers `item_swap_controller.js` as `item-swap` — no manual registration.
- AR currency display: `n.toLocaleString("es-AR", { minimumFractionDigits: 2, maximumFractionDigits: 2 })` (same approach as `on_account_payment_controller.js`).
- Preview mirrors the service's price rule: if the selected product id equals the original, use the line's `unit_price`; otherwise the selected product's `price_unit`.

- [ ] **Step 1: Create the Stimulus controller**

Create `app/javascript/controllers/item_swap_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

// Glue for the on_account item edit form: catches product-search selections,
// keeps the hidden product_id in sync and previews subtotal/total/balance.
export default class extends Controller {
  static targets = ["productId", "quantity", "selectedName", "selectedPrice",
                    "selectedBadge", "subtotal", "total", "balance", "submit"]
  static values = {
    originalProductId: Number,
    originalQuantity: Number,
    unitPrice: Number,   // current line price
    orderTotal: Number,
    orderPaid: Number
  }

  connect() {
    this.selectedCatalogPrice = this.unitPriceValue
    this.recompute()
  }

  productSelected(event) {
    const product = event.detail.product
    this.productIdTarget.value = product.id
    this.selectedNameTarget.textContent = `${product.name} · SKU ${product.sku}`
    this.selectedCatalogPrice = Number(product.price_unit) || 0
    this.selectedBadgeTarget.classList.toggle("hidden", product.id !== this.originalProductIdValue)
    this.recompute()
  }

  recompute() {
    const productId = parseInt(this.productIdTarget.value, 10)
    const quantity = parseInt(this.quantityTarget.value, 10) || 0
    const price = productId === this.originalProductIdValue
      ? this.unitPriceValue
      : this.selectedCatalogPrice

    const oldSubtotal = this.originalQuantityValue * this.unitPriceValue
    const newSubtotal = quantity * price
    const newTotal = this.orderTotalValue + (newSubtotal - oldSubtotal)
    const newBalance = newTotal - this.orderPaidValue

    this.selectedPriceTarget.textContent = `Precio catálogo: $ ${this.format(price)}`
    this.subtotalTarget.textContent = `$ ${this.format(oldSubtotal)} → $ ${this.format(newSubtotal)}`
    this.totalTarget.textContent = `$ ${this.format(this.orderTotalValue)} → $ ${this.format(newTotal)}`
    this.balanceTarget.textContent =
      `$ ${this.format(this.orderTotalValue - this.orderPaidValue)} → $ ${this.format(newBalance)}`

    const changed = productId !== this.originalProductIdValue ||
                    quantity !== this.originalQuantityValue
    this.submitTarget.disabled = !(changed && quantity >= 1)
  }

  format(n) {
    return Number(n).toLocaleString("es-AR", { minimumFractionDigits: 2, maximumFractionDigits: 2 })
  }
}
```

- [ ] **Step 2: Create the view**

Create `app/views/web/payments_on_account/items/edit.html.haml`:

```haml
- content_for :page_title, "Cambiar producto"

.container.mx-auto.px-6.py-6
  .flex.items-baseline.justify-between.mb-4
    %div
      %p.text-xs.font-medium.uppercase.tracking-wider.text-slate-500
        = "Talonario #{@order.paper_number} · #{@order.contact_name}"
      %h1.text-2xl.font-semibold.text-slate-900 Cambiar producto
    = link_to "← Volver a la operación", web_payments_on_account_path(@order), class: "text-sm text-slate-500 hover:text-slate-900"

  .bg-white.border.border-slate-200.rounded-2xl.p-5{ style: "max-width: 560px;",
    data: { controller: "item-swap",
            'item-swap-original-product-id-value': @item.product_id,
            'item-swap-original-quantity-value': @item.quantity,
            'item-swap-unit-price-value': @item.unit_price,
            'item-swap-order-total-value': @order.total_amount,
            'item-swap-order-paid-value': @order.total_amount - @order.outstanding_balance } }
    %h3.text-sm.font-semibold.text-slate-900.mb-3 Producto
    %div{ data: { controller: "product-search", 'product-search-url-value': search_web_products_path,
                  action: "click@window->product-search#clickOutside product-selected->item-swap#productSelected" },
          class: "mb-4 relative" }
      %input{ type: "text", placeholder: "Buscar por SKU, nombre o marca...", autocomplete: "off",
              class: "w-full px-4 py-2.5 border border-slate-300 rounded-lg focus:ring-2 focus:ring-slate-500 focus:border-transparent",
              data: { 'product-search-target': 'input', action: 'input->product-search#search' } }
      %div{ data: { 'product-search-target': 'results' },
            class: "absolute z-50 w-full mt-2 bg-white border border-slate-200 rounded-lg shadow-lg hidden",
            style: "max-height: 400px; overflow-y: scroll;" }

    = form_with url: web_payments_on_account_item_path(@order, @item), method: :patch do |f|
      = hidden_field_tag :product_id, @item.product_id, data: { 'item-swap-target': 'productId' }
      .text-sm.text-slate-800.mb-1
        Seleccionado:
        %span.font-semibold{ data: { 'item-swap-target': 'selectedName' } }
          = "#{@item.product.name} · SKU #{@item.product.sku}"
        %span.inline-block.border.border-slate-300.rounded-full.px-2.text-xs.text-slate-600{ data: { 'item-swap-target': 'selectedBadge' } } actual
      %p.text-xs.text-slate-500.mb-4{ data: { 'item-swap-target': 'selectedPrice' } }

      .border-t.border-slate-200.my-3
      %label.text-sm.text-slate-800{ for: "quantity" } Cantidad
      %div.mb-4
        = number_field_tag :quantity, @item.quantity, min: 1, id: "quantity",
          class: "w-24 px-3 py-2 border border-slate-300 rounded-lg text-center font-semibold",
          data: { 'item-swap-target': 'quantity', action: 'input->item-swap#recompute' }

      .border-t.border-slate-200.my-3
      .space-y-1.5.text-sm.mb-4
        .flex.justify-between.text-slate-600
          %span Subtotal
          %span{ data: { 'item-swap-target': 'subtotal' } }
        .flex.justify-between.text-slate-600
          %span Total de la operación
          %span{ data: { 'item-swap-target': 'total' } }
        .flex.justify-between.font-semibold.text-slate-900
          %span Saldo
          %span{ data: { 'item-swap-target': 'balance' } }

      .flex.justify-end.gap-2
        = link_to "Cancelar", web_payments_on_account_path(@order),
          class: "px-4 py-2 border border-slate-300 text-slate-700 rounded-xl text-sm font-medium hover:bg-slate-50"
        = f.submit "Guardar cambio", disabled: true,
          class: "px-4 py-2 bg-slate-900 text-white rounded-xl text-sm font-medium cursor-pointer disabled:bg-slate-300 disabled:cursor-not-allowed",
          data: { 'item-swap-target': 'submit' }
```

- [ ] **Step 3: Run the full request spec**

Run: `bundle exec rspec spec/requests/web/payments_on_account/items_spec.rb`
Expected: all green (GET edit now renders).

- [ ] **Step 4: Manual smoke test**

Run `bin/dev` (or `bin/rails s`), open an open on-account operation as vendedor/admin, navigate to an undelivered item's edit page:
- Current product pre-selected with "actual" pill; submit disabled.
- Search and pick another product → name/SKU/price update, preview shows old → new, submit enables.
- Change only the quantity → preview updates with the original line price, submit enables.
- Re-select the original product with original quantity → submit disables again.

---

### Task 5: Show view — row actions column

**Files:**
- Modify: `app/controllers/web/payments_on_account_controller.rb` (add `@can_edit_items` in `show`)
- Modify: `app/views/web/payments_on_account/show.html.haml` (products table)
- Test: `spec/requests/web/payments_on_account_spec.rb` (add examples)

**Interfaces:**
- Consumes: `PaymentOnAccountPolicy#edit_item?` (Task 1), `edit_web_payments_on_account_item_path` (Task 3).

- [ ] **Step 1: Write the failing request specs**

Add to the `describe "GET show role-based controls"` block in `spec/requests/web/payments_on_account_spec.rb`:

```ruby
it "shows the change-product action to a vendedor on undelivered rows only" do
  delivered = create(:order_item, :delivered, order: open_order, product: create(:product),
                     quantity: 1, unit_price: 100)
  sign_in vendedor
  get web_payments_on_account_path(open_order)

  undelivered_path = edit_web_payments_on_account_item_path(open_order, open_order.order_items.first)
  delivered_path   = edit_web_payments_on_account_item_path(open_order, delivered)
  expect(response.body).to include("Cambiar")
  expect(response.body).to include(undelivered_path)
  expect(response.body).not_to include(delivered_path)
end

it "hides the change-product action from caja" do
  sign_in caja
  get web_payments_on_account_path(open_order)
  expect(response.body).not_to include("Cambiar")
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/requests/web/payments_on_account_spec.rb`
Expected: the 2 new examples fail (no "Cambiar" in the page yet).

- [ ] **Step 3: Expose the policy in the controller**

In `app/controllers/web/payments_on_account_controller.rb#show`, after `@can_collect`:

```ruby
@can_edit_items = policy.edit_item?
```

- [ ] **Step 4: Add the actions column to the table**

In `app/views/web/payments_on_account/show.html.haml`:

Header row — add a fourth `%th` after the Entrega header:

```haml
%th.py-1.5.font-medium.border-b.border-slate-100
```

Body rows — add a fourth `%td` after the Entrega cell (same indent level as the other `%td`):

```haml
%td.py-2.5.text-center
  - if @can_edit_items && item.delivered_at.nil?
    = link_to edit_web_payments_on_account_item_path(@order, item),
      class: "inline-flex items-center gap-1 px-2.5 py-1 border border-slate-300 rounded-lg text-xs font-medium text-slate-700 hover:bg-slate-50" do
      ⇄ Cambiar
  - else
    %span.text-xs.text-slate-300 —
```

- [ ] **Step 5: Run to verify pass**

Run: `bundle exec rspec spec/requests/web/payments_on_account_spec.rb`
Expected: all green (including the pre-existing examples — the extra `—` column must not break them).

---

### Task 5b: Testing-layer compliance (added during execution)

The Task 4 review found the plan did not satisfy `AGENTS.md` §Testing Rules:
rule 2 (hostile-input case in the request spec) and rule 3 (minimal system
spec when correctness depends on Stimulus — disabled submit, live
recalculation). The user approved adding both before closing the branch.

**Files:**
- Modify: `spec/requests/web/payments_on_account/items_spec.rb` — hostile
  input: non-numeric / negative / blank quantity, unknown product id,
  product with no catalog price. Each asserts the redirect back to edit,
  the Spanish error, and that neither the line nor the order total moved.
- Create: `spec/system/web/payments_on_account_item_swap_spec.rb` — one
  example: submit starts disabled, changing the quantity enables it and
  updates the preview live, restoring the original quantity disables it
  again. Visits the edit path directly (the existing
  `spec/system/web/payments_on_account_spec.rb` fails at the index on a
  **pre-existing** unrelated issue, verified on a clean worktree at
  `b6f20a3` — do not modify it here).

Full task detail: `.superpowers/sdd/task-5b-brief.md`.

---

### Task 6: Documentation, lint, full suite, handoff

**Files:**
- Modify: `WORKING_CONTEXT.md` (Payments on account section)

- [ ] **Step 1: Document the feature + known gap in WORKING_CONTEXT.md**

In the "Payments on account (`on_account`)" section, after the per-item delivery bullet, add:

```markdown
* **Per-item product swap (feat_22)**: vendedor/admin can replace the product and/or quantity of an **undelivered** line from the detail view (`Web::PaymentsOnAccount::ItemsController` edit/update → `Sales::ReplaceOrderItem`). The new line price is the chosen product's catalog `price_unit` (rejected if not > 0); a quantity-only edit keeps the line's original price. The delta is applied to **both** `total_amount` and `original_total_amount` (never re-summed — that would wipe effective discounts), then `refresh_status_from_balance!` runs (a pricier swap can reopen a confirmed order). No stock movements. **Known gap (accepted):** there is no overpayment guard — a swap below the collected amount leaves a negative `outstanding_balance` on screen and auto-confirms the order; the excess is not recorded anywhere.
```

- [ ] **Step 2: Lint**

Run: `bundle exec rubocop`
Expected: no offenses. Fix any that appear (`bundle exec rubocop -a` for autocorrectables).

- [ ] **Step 3: Full test suite**

Run: `bundle exec rspec`
Expected: all green, no pre-existing spec broken.

- [ ] **Step 4: Stage and hand over the commit message (do NOT commit)**

```bash
git add app/ config/routes.rb spec/ WORKING_CONTEXT.md docs/superpowers/
```

Hand the user this message:

```
feat(feat_22): swap products on undelivered payments-on-account lines

Vendedor/admin can replace the product and/or quantity of any line not
yet marked as delivered, from a new edit page reached via a row action
on the operation detail. The new line price always comes from the
chosen product's catalog price (no price input); quantity-only edits
keep the original line price. Sales::ReplaceOrderItem applies the
subtotal delta to both total_amount and original_total_amount so
effective discounts from prior collections are preserved, then
refreshes the order status. No overpayment guard by decision: a swap
below the collected amount is documented as a known gap in
WORKING_CONTEXT.md.
```

---

## Self-review notes

- Spec coverage: decisions 1-8 map to Tasks 1-6 (roles→T1, service/delta/price rules→T2, routes/controller→T3, form/preview→T4, row action→T5, known-gap doc→T6). Edge cases (concurrent delivery, reopen on pricier swap, negative balance) are covered in T2/T3 specs.
- The delivered-row visibility rule is enforced twice by design: view (T5) and service/controller (T2/T3).
- No commits anywhere per project rules; single handoff message with scope `feat_22`.
```
