# Post-features fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply seven small, independent UI/behavior fixes accumulated after several features.

**Architecture:** Almost entirely view (HAML) and Stimulus (JS) changes plus one model whitelist line. No service/model logic changes. No new automated tests required — verification is the existing suite (must stay green) plus manual browser checks per view.

**Tech Stack:** Rails 7.2, HAML, TailwindCSS, Hotwire/Stimulus.

> **NO COMMITS.** Per the user's instruction, do **not** run `git commit` or `git add`. The user will commit manually. Each task ends with verification only.

> **Spec reference:** `docs/superpowers/specs/2026-06-03-post-features-fixes-design.md`

---

## File Structure

- `app/models/product.rb` — add `price_unit` to the sort whitelist (Task 1).
- `app/views/web/products/index.html.haml` — price column + cart modal total (Tasks 1, 2).
- `app/javascript/controllers/cart_controller.js` — cart line price + total (Task 2).
- `app/views/web/orders/new.html.haml` — hidden `from_paper` source + sticky layout (Tasks 3, 4).
- `app/javascript/controllers/product_search_controller.js` — drop zero-stock block (Task 3).
- `app/javascript/controllers/order_form_controller.js` — drop quantity cap (Task 3).
- `WORKING_CONTEXT.md` — document paper-mode default (Task 3).
- `app/views/web/customers/payments/new.html.haml` — currency text field + submit cleaning (Task 5).
- `app/javascript/controllers/payment_allocation_controller.js` — parse/format AR amounts (Task 5).
- `app/views/web/products/_form.html.haml` — remove category, disable USD (Tasks 6, 7).

---

## Task 1: products index — replace "Estado" column with "Precio"

**Files:**
- Modify: `app/models/product.rb` (sort whitelist, ~line 94)
- Modify: `app/views/web/products/index.html.haml` (header ~82-83, cell ~137-142)

- [ ] **Step 1: Add `price_unit` to the sort whitelist**

In `app/models/product.rb`, inside the `sorted_by` scope, change:

```ruby
    allowed_columns = %w[sku name brand category current_stock]
```

to:

```ruby
    allowed_columns = %w[sku name brand category current_stock price_unit]
```

- [ ] **Step 2: Replace the column header**

In `app/views/web/products/index.html.haml`, find the `ESTADO` header:

```haml
            %th.px-4.py-3.text-left.text-xs.font-medium.text-slate-500.uppercase.tracking-wider
              ESTADO
```

Replace with:

```haml
            %th.px-4.py-3.text-left.text-xs.font-medium.text-slate-500.uppercase.tracking-wider
              = sortable_column(:price_unit, "PRECIO", params)
```

- [ ] **Step 3: Replace the status badge cell with the price**

Find the Estado cell:

```haml
                -# Estado
                %td.px-4.py-3.whitespace-nowrap
                  - if product.active?
                    %span.badge-success Activo
                  - else
                    %span.badge-neutral Inactivo
```

Replace with:

```haml
                -# Precio
                %td.px-4.py-3.whitespace-nowrap
                  %span.text-sm.font-medium.text-slate-900= product.price_unit.present? ? currency_ar(product.price_unit) : "—"
```

- [ ] **Step 4: Verify**

Run: `bundle exec rubocop app/models/product.rb`
Expected: no offenses.

Manual: open `/web/products`. The last data column before "Acciones" now reads "PRECIO" and shows e.g. `ARS 1.234,56` (or `—` when no price). The "Estado"/"Activo" badge is gone. The status filter dropdown still appears and still filters. Clicking the "PRECIO" header sorts.

---

## Task 2: cart modal — show unit price per line and a total

**Files:**
- Modify: `app/views/web/products/index.html.haml` (cart modal footer, ~39-42)
- Modify: `app/javascript/controllers/cart_controller.js`

- [ ] **Step 1: Add a Total row and `cartTotal` target to the modal footer**

In `app/views/web/products/index.html.haml`, find the cart modal footer:

```haml
    .px-5.py-4.border-t.border-slate-100.flex.justify-end
      = link_to "Crear venta", "#",
        data: { cart_target: "createButton" },
        class: "inline-flex items-center gap-2 px-4 py-2 bg-slate-700 hover:bg-slate-800 text-white text-sm font-semibold rounded-lg shadow-sm transition-colors opacity-50 pointer-events-none"
```

Replace with:

```haml
    .px-5.py-4.border-t.border-slate-100.space-y-3
      .flex.items-center.justify-between
        %span.text-sm.font-medium.text-slate-600 Total
        %span.text-base.font-bold.text-slate-900{ data: { cart_target: "cartTotal" } } $0,00
      .flex.justify-end
        = link_to "Crear venta", "#",
          data: { cart_target: "createButton" },
          class: "inline-flex items-center gap-2 px-4 py-2 bg-slate-700 hover:bg-slate-800 text-white text-sm font-semibold rounded-lg shadow-sm transition-colors opacity-50 pointer-events-none"
```

- [ ] **Step 2: Register the `cartTotal` target**

In `app/javascript/controllers/cart_controller.js`, change:

```js
  static targets = ["panel", "items", "count", "createButton", "backdrop"]
```

to:

```js
  static targets = ["panel", "items", "count", "createButton", "backdrop", "cartTotal"]
```

- [ ] **Step 3: Render unit price + line subtotal in each cart row**

In `renderPanel`, replace the row template (the `.map(...)` block) with:

```js
    this.itemsTarget.innerHTML = this.cartItems.map((item, index) => `
      <div class="flex items-center gap-3 py-3 border-b border-slate-100 last:border-0">
        <div class="flex-1 min-w-0">
          <p class="text-sm font-semibold text-slate-900 truncate">${item.name}</p>
          <p class="text-xs text-slate-500">${item.sku} · Stock: ${item.current_stock}</p>
          <p class="text-xs text-slate-600 mt-0.5">${this.formatMoney(item.price_unit)} c/u</p>
        </div>
        <input
          type="number"
          value="${item.quantity}"
          min="1"
          class="w-16 px-2 py-1 text-sm border border-slate-300 rounded-lg text-center"
          data-action="change->cart#updateQuantity"
          data-cart-index="${index}"
        />
        <span class="w-24 text-right text-sm font-semibold text-slate-900">${this.formatMoney(item.price_unit * item.quantity)}</span>
        <button
          type="button"
          class="text-slate-400 hover:text-red-500 transition-colors"
          data-action="click->cart#removeItem"
          data-cart-index="${index}"
        >✕</button>
      </div>
    `).join("")
```

- [ ] **Step 4: Add a `updateTotal` call to both `renderPanel` branches and to `updateQuantity`**

In `renderPanel`, the empty-cart branch currently ends with `this.updateCreateButton(); return`. Add `this.updateTotal()` before `return`:

```js
    if (this.cartItems.length === 0) {
      this.itemsTarget.innerHTML = `
        <p class="text-sm text-slate-500 text-center py-6">No hay productos en el carrito.</p>
      `
      this.updateCreateButton()
      this.updateTotal()
      return
    }
```

At the end of `renderPanel` (after the existing `this.updateCreateButton()`), add:

```js
    this.updateCreateButton()
    this.updateTotal()
```

In `updateQuantity`, after `this.updateCreateButton()`, add `this.updateTotal()`:

```js
    this.cartItems[index].quantity = value
    this.updateCount()
    this.updateCreateButton()
    this.updateTotal()
```

- [ ] **Step 5: Add the `updateTotal` and `formatMoney` helper methods**

Add these two methods to the controller (e.g. just before `buildUrl()`):

```js
  updateTotal() {
    if (!this.hasCartTotalTarget) return
    const total = this.cartItems.reduce((sum, i) => sum + i.price_unit * i.quantity, 0)
    this.cartTotalTarget.textContent = this.formatMoney(total)
  }

  formatMoney(value) {
    return "$" + new Intl.NumberFormat("es-AR", {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    }).format(value || 0)
  }
```

- [ ] **Step 6: Verify**

Manual: open `/web/products`, add a couple of products to the cart, open the cart modal. Each line shows `$X,XX c/u` and a right-aligned line subtotal; the footer shows a "Total" that updates when you change quantities or remove items.

---

## Task 3: orders/new — allow selling without stock (paper mode default)

**Files:**
- Modify: `app/views/web/orders/new.html.haml` (add hidden source field)
- Modify: `app/javascript/controllers/product_search_controller.js` (`selectProduct`)
- Modify: `app/javascript/controllers/order_form_controller.js` (`updateQuantity`, `renderItems`)
- Modify: `WORKING_CONTEXT.md`

- [ ] **Step 1: Submit `source: from_paper` from the order form**

In `app/views/web/orders/new.html.haml`, immediately after the `form_with ... do |f|` line (the line that begins `= form_with model: @order`), add a hidden field as the first line inside the form:

```haml
    = hidden_field_tag :source, "from_paper"
```

(Keep the existing indentation of the form body — two spaces deeper than `form_with`.)

- [ ] **Step 2: Remove the zero-stock block in product search**

In `app/javascript/controllers/product_search_controller.js`, in `selectProduct`, delete this block entirely:

```js
    // Solo validar stock si NO estamos en un formulario de compra
    const isInvoiceForm = this.element.closest('[data-controller*="invoice-form"]')
    if (!isInvoiceForm && product.current_stock <= 0) {
      alert('Este producto no tiene stock disponible')
      return
    }

```

After deletion, `selectProduct` starts by parsing the product and dispatching the event:

```js
  selectProduct(event) {
    const product = JSON.parse(event.currentTarget.dataset.product)

    const customEvent = new CustomEvent('product-selected', {
      detail: { product },
      bubbles: true
    })
    this.element.dispatchEvent(customEvent)

    this.inputTarget.value = ''
    this.hideResults()
  }
```

- [ ] **Step 3: Remove the quantity cap in the order form (logic)**

In `app/javascript/controllers/order_form_controller.js`, change `updateQuantity` from:

```js
  updateQuantity(event) {
    const index = parseInt(event.currentTarget.dataset.index)
    const newQuantity = parseInt(event.currentTarget.value)

    if (newQuantity > 0 && newQuantity <= this.items[index].max_stock) {
      this.items[index].quantity = newQuantity
      this.updateItemSubtotal(index)
      this.updateSummary()
    }
  }
```

to:

```js
  updateQuantity(event) {
    const index = parseInt(event.currentTarget.dataset.index)
    const newQuantity = parseInt(event.currentTarget.value)

    if (newQuantity > 0) {
      this.items[index].quantity = newQuantity
      this.updateItemSubtotal(index)
      this.updateSummary()
    }
  }
```

- [ ] **Step 4: Remove the `max` attribute on the rendered quantity input**

In `order_form_controller.js`, inside `renderItems`, delete the `max="${item.max_stock}"` line from the quantity `<input>` so it reads:

```js
            <input
              type="number"
              value="${item.quantity}"
              min="1"
              data-index="${index}"
              data-action="input->order-form#updateQuantity"
              class="w-20 px-2 py-1.5 border border-gray-300 rounded-lg text-center font-semibold"
            />
```

- [ ] **Step 5: Update WORKING_CONTEXT.md**

In `WORKING_CONTEXT.md`, find the line under "Key constraints" / "Order validation":

```
* **`Order` validation:** `paper_number` is **required for every order** (unconditional `presence: true`, not unique). `Sales::CreateOrder` validates stock availability for `source: 'live'` only; it skips the check for `from_paper`.
```

Replace with:

```
* **`Order` validation:** `paper_number` is **required for every order** (unconditional `presence: true`, not unique). `Sales::CreateOrder` validates stock availability for `source: 'live'` only; it skips the check for `from_paper`. **`web/orders/new` submits `source: from_paper` by default** (hidden field), so the UI sales flow does **not** validate stock at sale time — the vendor is trusted to know the product exists (no inventory system yet). The `live` branch and its stock validation remain in the service for future use.
```

- [ ] **Step 6: Verify**

Run: `bundle exec rspec spec/services/sales/create_order_spec.rb`
Expected: PASS (service unchanged; both `live` and `from_paper` contexts stay green).

Manual: open `/web/orders/new`, search a product with `Sin stock`, click it — it is added (no alert). Increase its quantity beyond stock — accepted. Submit a valid note — it creates successfully.

---

## Task 4: orders/new — summary always sticky on the right

**Files:**
- Modify: `app/views/web/orders/new.html.haml` (cards grid, ~43-133)

- [ ] **Step 1: Restructure the cards grid into left stack + right sticky summary**

Replace the entire block that starts at `.grid.grid-cols-1.md:grid-cols-2.gap-6` and contains the three cards (Información del Cliente, Productos, Resumen de Venta) with the structure below. Wrap the two left cards in a `col-span-2` stack and the summary in a `col-span-1` column. Preserve each card's inner content exactly — only the outer wrappers and indentation change.

```haml
    .grid.grid-cols-1.lg:grid-cols-3.gap-6

      -# ============ Columna izquierda: Cliente + Productos ============
      .lg:col-span-2.space-y-6

        -# Card - Información del Cliente
        .bg-white.border.border-slate-200.rounded-lg.p-6
          %h3.text-lg.font-semibold.text-gray-900.mb-4 Información del Cliente

          .space-y-4
            -# Tipo de venta (radio buttons visuales)
            %div
              %label.block.text-sm.font-medium.text-gray-700.mb-3 Tipo de Venta
              .grid.grid-cols-2.gap-4
                %div{ class: "relative flex items-center gap-3 p-4 border-2 border-gray-200 rounded-xl cursor-pointer hover:border-gray-400 transition-all" }
                  %span
                    = f.radio_button :order_type, "immediate", checked: true, id: "order_type_immediate", data: { action: "change->order-form#updateOrderType", "order-form-target": "immediateRadio" }
                  %label.cursor-pointer.flex-1{ for: "order_type_immediate" }
                    %p.font-medium.text-gray-900 💵 Contado
                    %p.text-xs.text-gray-500 Pago inmediato

                %div{ class: "relative flex items-center gap-3 p-4 border-2 border-gray-200 rounded-xl cursor-pointer hover:border-gray-400 transition-all" }
                  %span
                    = f.radio_button :order_type, "credit", id: "order_type_credit", data: { action: "change->order-form#updateOrderType", "order-form-target": "creditRadio" }
                  %label.cursor-pointer.flex-1{ for: "order_type_credit" }
                    %p.font-medium.text-gray-900 📋 Cuenta Corriente
                    %p.text-xs.text-gray-500 A crédito

            -# Selector de cliente
            - customer_options = [["Cliente Mostrador", "mostrador", { "data-has-credit-account" => "false" }]]
            - @customers.each do |c|
              - customer_options << ["#{c.name}#{c.has_credit_account? ? ' (Cuenta Corriente)' : ''}", c.id, { "data-has-credit-account" => c.has_credit_account.to_s }]
            %div
              = f.label :customer_id, "Cliente", class: "block text-sm font-medium text-gray-700 mb-2"
              = f.select :customer_id, options_for_select(customer_options, "mostrador"), {}, class: "w-full px-4 py-3 border border-gray-300 rounded-xl focus:ring-2 focus:ring-gray-700 focus:border-transparent transition-all", data: { action: "change->order-form#customerChanged" }
              %p.text-xs.text-gray-500.mt-1 Para ventas a crédito, selecciona un cliente con cuenta corriente

            -# Canal de venta
            %div
              = f.label :channel, "Canal de Venta", class: "block text-sm font-medium text-gray-700 mb-2"
              = f.select :channel, options_for_select([["🏪 Mostrador", "counter"], ["💬 WhatsApp", "whatsapp"], ["🛒 Mercado Libre", "mercadolibre"]], "counter"), {}, class: "w-full px-4 py-3 border border-gray-300 rounded-xl focus:ring-2 focus:ring-gray-700 focus:border-transparent transition-all"

        -# Card - Productos
        .bg-white.border.border-slate-200.rounded-lg.p-6
          %h3.text-lg.font-semibold.text-gray-900.mb-4 Productos

          -# Search input con dropdown
          %div{ data: { controller: "product-search", 'product-search-url-value': search_web_products_path, action: "click@window->product-search#clickOutside product-selected->order-form#addProduct" }, class: "mb-6 relative" }
            %input{ type: "text", placeholder: "Buscar por SKU, nombre o marca...", autocomplete: "off", class: "w-full px-5 py-3 border border-slate-300 rounded-lg focus:ring-2 focus:ring-slate-500 focus:border-transparent transition-all", data: { 'product-search-target': 'input', action: 'input->product-search#search' } }
            %div{ data: { 'product-search-target': 'results' }, class: "absolute z-50 w-full mt-2 bg-white border border-slate-200 rounded-lg shadow-lg hidden", style: "max-height: 400px; overflow-y: scroll;" }

          -# Lista de productos agregados
          .mt-6
            #order-items{ data: { 'order-form-target': 'items' } }
              .text-center.py-12.text-gray-400
                %p.text-5xl.mb-3 📦
                %p.text-gray-600.font-medium No hay productos agregados
                %p.text-sm.text-gray-500.mt-1 Buscá y seleccioná productos usando el campo de arriba

      -# ============ Columna derecha: Resumen sticky ============
      .lg:col-span-1
        .bg-white.border.border-slate-200.rounded-lg.p-6.lg:sticky.lg:top-24
          %h3.text-lg.font-semibold.text-gray-900.mb-6 Resumen de Venta

          -# Total principal (calculado dinámicamente)
          .text-center.mb-6
            %p.text-sm.text-gray-500.mb-2 Total
            %p.text-4xl.font-bold.text-gray-900{ data: { order_form_target: "total" } } $0

          .border-t.border-gray-200.py-4.space-y-3
            .flex.justify-between.text-sm
              %span.text-gray-600 Items
              %span.font-medium.text-gray-900{ data: { order_form_target: "itemCount" } } 0 productos

            .flex.justify-between.text-sm
              %span.text-gray-600 Cantidad total
              %span.font-medium.text-gray-900{ data: { order_form_target: "totalQuantity" } } 0 unidades

          .border-t.border-gray-200.py-4
            %h4.text-sm.font-semibold.text-gray-900.mb-3 Información de Pago

            .space-y-2
              .flex.items-center.gap-2.text-sm{ data: { order_form_target: "orderTypeInfo" } }
                %span 💵
                %span.text-gray-600 Contado - Pago inmediato

              .flex.items-center.gap-2.text-sm
                %span 🏪
                %span.text-gray-600 Mostrador

          .border-t.border-gray-200.pt-4
            = f.submit "Crear nota de pedido", disabled: true, class: "w-full inline-flex items-center justify-center gap-2 px-4 py-3 bg-slate-700 hover:bg-slate-800 text-white text-base font-semibold rounded-lg shadow-sm transition-colors opacity-50 cursor-not-allowed", data: { order_form_target: "submitButton" }

          .mt-4.text-center
            %p.text-xs.text-gray-500 La nota queda pendiente de cobro
```

- [ ] **Step 2: Verify**

Manual: open `/web/orders/new` on a wide screen. "Resumen de Venta" is in a narrow right column, sticky on scroll. "Información del Cliente" and "Productos" are stacked in the left column (Productos below Cliente). Add products and scroll — the summary stays pinned on the right and never drops below the product list. On mobile (`grid-cols-1`) the cards stack in order: Cliente, Productos, Resumen.

---

## Task 5: payments/new — "Cobrar" AR decimal formatting

**Files:**
- Modify: `app/views/web/customers/payments/new.html.haml` (form tag ~41, amount input ~118-122)
- Modify: `app/javascript/controllers/payment_allocation_controller.js`

- [ ] **Step 1: Add `product-form` controller + submit-clean action to the form**

In `app/views/web/customers/payments/new.html.haml`, change the form opening line:

```haml
    = form_with url: web_customer_payments_path(@customer), method: :post, local: true, data: { controller: "payment-allocation", "payment-allocation-total-debt-value": total_debt.to_s } do
```

to:

```haml
    = form_with url: web_customer_payments_path(@customer), method: :post, local: true, data: { controller: "payment-allocation product-form", action: "turbo:submit-start->product-form#handleSubmit", "payment-allocation-total-debt-value": total_debt.to_s } do
```

- [ ] **Step 2: Switch the amount input to a currency text field**

Find the amount input:

```haml
                  = number_field_tag "allocations[#{idx}][amount]", nil,
                      step: "0.01", min: "0",
                      disabled: true,
                      class: "w-32 px-2 py-1 text-right text-sm font-semibold border border-slate-300 rounded disabled:bg-slate-50 disabled:text-slate-400",
                      data: { "role": "amount-input", action: "input->payment-allocation#recalc" }
```

Replace with:

```haml
                  = text_field_tag "allocations[#{idx}][amount]", nil,
                      disabled: true,
                      class: "w-32 px-2 py-1 text-right text-sm font-semibold border border-slate-300 rounded disabled:bg-slate-50 disabled:text-slate-400",
                      data: { controller: "currency-input", "role": "amount-input", action: "input->payment-allocation#recalc blur->currency-input#format focus->currency-input#unformat" }
```

- [ ] **Step 3: Parse AR-formatted amounts in `updateSummary`**

In `app/javascript/controllers/payment_allocation_controller.js`, in `updateSummary`, change:

```js
      if (checkbox.checked && amountInput.value) {
        const v = parseFloat(amountInput.value) || 0
        charging += v
        if (v > 0) selected += 1
      }
```

to:

```js
      if (checkbox.checked && amountInput.value) {
        const v = this.parseAmount(amountInput.value)
        charging += v
        if (v > 0) selected += 1
      }
```

- [ ] **Step 4: Format the auto-filled amount in `recomputeCard`**

In `recomputeCard`, change:

```js
    if (checkbox.checked) {
      amountInput.value = newSum.toFixed(2)
    }
```

to:

```js
    if (checkbox.checked) {
      amountInput.value = this.formatAmount(newSum)
    }
```

- [ ] **Step 5: Add the `parseAmount` and `formatAmount` helpers**

Add these two methods to the controller (e.g. just before `formatMoney`):

```js
  parseAmount(value) {
    if (!value) return 0
    return parseFloat(value.replace(/\./g, "").replace(/,/g, ".")) || 0
  }

  formatAmount(value) {
    return new Intl.NumberFormat("es-AR", {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    }).format(value || 0)
  }
```

- [ ] **Step 6: Verify**

Run: `bundle exec rspec spec/requests/web/customers/payments_spec.rb`
Expected: PASS (request specs POST raw params; rendering change doesn't affect them).

Manual: open `/web/customers/:id/payments/new` for a customer with pending credit orders. Tick an order — "Cobrar" prefills as `1.234,56` (AR format). Type a custom amount; on blur it formats to AR style; the "Cobrando ahora" / "Saldo restante" summary updates correctly. Submit — the cobro registers with the right amount (server receives a clean decimal).

---

## Task 6: products/new — remove "Categoría" field

**Files:**
- Modify: `app/views/web/products/_form.html.haml` (Card 3 — Clasificación)

- [ ] **Step 1: Remove the category select block**

In `app/views/web/products/_form.html.haml`, delete this block (inside Card 3, between "Tipo de Producto" and "Origen"):

```haml
          %div
            = f.label :category, "Categoría", class: "block text-sm font-medium text-slate-700 mb-2"
            = f.select :category,
                      options_for_select([["Seleccionar categoría", ""]] + Product::CATEGORIES.map { |c| [c.titleize, c] }, product.category),
                      {},
                      class: "w-full px-4 py-3 border border-slate-300 rounded-lg focus:ring-2 focus:ring-slate-500 focus:border-transparent transition-all"
```

After deletion, Card 3 contains only "Tipo de Producto" and "Origen". No model change — `Product` has no presence constraint on `category` (only `inclusion: { in: CATEGORIES, allow_blank: true }`).

- [ ] **Step 2: Verify**

Run: `bundle exec rspec spec/models/product_spec.rb`
Expected: PASS.

Manual: open `/web/products/new`. The "Categoría" select is gone. Create a product without a category — it saves successfully.

---

## Task 7: products/new — cost currency default ARS, USD disabled

**Files:**
- Modify: `app/views/web/products/_form.html.haml` (Card 2 — Moneda del Costo)

- [ ] **Step 1: Disable the USD radio and gray out its container**

In `app/views/web/products/_form.html.haml`, find the USD option:

```haml
              %div{class: "relative flex items-center gap-3 p-4 border-2 border-slate-200 rounded-lg cursor-pointer hover:border-slate-500 transition-all"}
                %span
                  = f.radio_button :cost_currency, "USD", checked: product.cost_currency == 'USD', id: "cost_currency_usd"
                %label.cursor-pointer.flex-1{for: "cost_currency_usd"}
                  %p.font-medium.text-slate-900 USD
                  %p.text-xs.text-slate-500 Dólar estadounidense
```

Replace with:

```haml
              %div{class: "relative flex items-center gap-3 p-4 border-2 border-slate-200 rounded-lg opacity-50 cursor-not-allowed"}
                %span
                  = f.radio_button :cost_currency, "USD", checked: product.cost_currency == 'USD', disabled: true, id: "cost_currency_usd"
                %label.flex-1{for: "cost_currency_usd"}
                  %p.font-medium.text-slate-900 USD
                  %p.text-xs.text-slate-500 Dólar estadounidense
```

- [ ] **Step 2: Default the ARS radio to checked**

Find the ARS option radio:

```haml
                  = f.radio_button :cost_currency, "ARS", checked: product.cost_currency == 'ARS', id: "cost_currency_ars"
```

Replace with:

```haml
                  = f.radio_button :cost_currency, "ARS", checked: product.cost_currency != 'USD', id: "cost_currency_ars"
```

- [ ] **Step 3: Verify**

Manual: open `/web/products/new`. ARS is selected by default; the USD option is grayed and unclickable. Save a product — `cost_currency` persists as `ARS`. Editing an existing product whose cost is USD shows USD checked but disabled.

---

## Final verification

- [ ] **Run the full suite**

Run: `bundle exec rspec`
Expected: all green (no behavior/logic changed beyond the `price_unit` sort whitelist).

- [ ] **Lint**

Run: `bundle exec rubocop`
Expected: no new offenses in touched files.

- [ ] **Manual pass**

Walk through each affected view once more: `/web/products` (price column + cart total), `/web/orders/new` (no-stock add + sticky summary), `/web/customers/:id/payments/new` (AR amount), `/web/products/new` (no category, ARS default / USD disabled).

- [ ] **Hand off to the user for commit** (do NOT commit yourself).
