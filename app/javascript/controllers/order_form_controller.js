import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["items", "total", "itemCount", "totalQuantity", "submitButton", "orderTypeInfo", "creditRadio", "immediateRadio"]
  static values = { initialItems: Array }

  connect() {
    this.items = this.initialItemsValue.length > 0 ? this.initialItemsValue : []
    this.renderItems()
    this.updateSummary()
    this.applyCreditRadioState()
  }

  customerChanged(event) {
    const select = event.target
    const selectedOption = select.options[select.selectedIndex]
    this.applyCreditRadioStateForOption(selectedOption)
    this.updateSubmitButton()
  }

  applyCreditRadioState() {
    const customerSelect = this.element.querySelector('select[name="order[customer_id]"]')
    if (!customerSelect) return

    const selectedOption = customerSelect.options[customerSelect.selectedIndex]
    this.applyCreditRadioStateForOption(selectedOption)
  }

  applyCreditRadioStateForOption(selectedOption) {
    if (!this.hasCreditRadioTarget) return

    const hasCreditAccount = selectedOption && selectedOption.dataset.hasCreditAccount === "true"

    if (hasCreditAccount) {
      this.creditRadioTarget.disabled = false
    } else {
      if (this.creditRadioTarget.checked && this.hasImmediateRadioTarget) {
        this.immediateRadioTarget.checked = true
        this.immediateRadioTarget.dispatchEvent(new Event('change', { bubbles: true }))
      }
      this.creditRadioTarget.disabled = true
    }
  }

  addProduct(event) {
    const product = event.detail.product

    const existingIndex = this.items.findIndex(item => item.product_id === product.id)

    if (existingIndex >= 0) {
      this.items[existingIndex].quantity += 1
    } else {
      this.items.push({
        product_id: product.id,
        sku: product.sku,
        name: product.name,
        brand: product.brand,
        quantity: 1,
        price_unit: product.price_unit || 0,
        max_stock: product.current_stock,
        origin: product.origin,
        product_type: product.product_type
      })
    }

    this.renderItems()
    this.updateSummary()
  }

  removeItem(event) {
    const index = parseInt(event.currentTarget.dataset.index)
    this.items.splice(index, 1)
    this.renderItems()
    this.updateSummary()
  }

  updateQuantity(event) {
    const index = parseInt(event.currentTarget.dataset.index)
    const newQuantity = parseInt(event.currentTarget.value)

    if (newQuantity > 0 && newQuantity <= this.items[index].max_stock) {
      this.items[index].quantity = newQuantity
      this.updateItemSubtotal(index)
      this.updateSummary()
    }
  }

  formatInputValue(value) {
    return new Intl.NumberFormat('es-AR', {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    }).format(value || 0)
  }

  updateItemSubtotal(index) {
    const item = this.items[index]
    const subtotal = item.price_unit * item.quantity

    const itemElements = this.itemsTarget.querySelectorAll('[data-item-index]')
    if (itemElements[index]) {
      const subtotalElement = itemElements[index].querySelector('[data-subtotal]')
      if (subtotalElement) {
        subtotalElement.textContent = `$${this.formatCurrency(subtotal)}`
      }

      const quantityInput = itemElements[index].querySelector('input[name="purchase_items[][quantity]"]')
      const priceInput = itemElements[index].querySelector('input[name="purchase_items[][unit_price]"]')
      if (quantityInput) quantityInput.value = item.quantity
      if (priceInput) priceInput.value = item.price_unit
    }
  }

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
  }

  calculateTotal() {
    return this.items.reduce((sum, item) => sum + (item.price_unit * item.quantity), 0)
  }

  renderItems() {
    if (this.items.length === 0) {
      this.itemsTarget.innerHTML = `
        <div class="text-center py-12 text-gray-400">
          <p class="text-5xl mb-3">📦</p>
          <p class="text-gray-600 font-medium">No hay productos agregados</p>
          <p class="text-sm text-gray-500 mt-1">Buscá y seleccioná productos usando el campo de arriba</p>
        </div>
      `
      return
    }

    const html = this.items.map((item, index) => `
      <div class="flex items-center gap-4 p-4 border border-gray-200 rounded-xl bg-white hover:shadow-sm transition-all" data-item-index="${index}">
        <div class="w-12 h-12 rounded-lg bg-gray-100 flex items-center justify-center text-xl flex-shrink-0">
          📦
        </div>

        <div class="flex-1 min-w-0">
          <div class="flex items-center gap-2 mb-1">
            <span class="font-mono text-xs text-gray-500 font-semibold">${item.sku}</span>
            ${item.product_type === 'oem' ? '<span class="px-2 py-0.5 bg-gray-100 text-gray-700 text-xs rounded-full">OEM</span>' : ''}
            ${item.product_type === 'aftermarket' ? '<span class="px-2 py-0.5 bg-blue-100 text-blue-700 text-xs rounded-full">ALT</span>' : ''}
          </div>
          <h4 class="font-semibold text-gray-900 text-sm truncate">${item.name}</h4>
          <p class="text-xs text-gray-500 mt-0.5">${item.brand || ''} ${item.origin ? '• ' + item.origin : ''}</p>
          <input type="hidden" name="purchase_items[][product_id]" value="${item.product_id}" />
          <input type="hidden" name="purchase_items[][quantity]" value="${item.quantity}" />
          <input type="hidden" name="purchase_items[][unit_price]" value="${item.price_unit}" />
        </div>

        <div class="flex items-center gap-3">
          <div class="text-right">
            <p class="text-xs text-gray-500">Cantidad</p>
            <input
              type="number"
              value="${item.quantity}"
              min="1"
              max="${item.max_stock}"
              data-index="${index}"
              data-action="input->order-form#updateQuantity"
              class="w-20 px-2 py-1.5 border border-gray-300 rounded-lg text-center font-semibold"
            />
          </div>

          <div class="text-right">
            <p class="text-xs text-gray-500">Precio Unit.</p>
            <p class="w-28 px-2 py-1.5 text-right font-semibold text-gray-900">$${this.formatInputValue(item.price_unit)}</p>
          </div>

          <div class="text-right min-w-[110px]">
            <p class="text-xs text-gray-500">Subtotal</p>
            <p class="text-lg font-bold text-gray-900" data-subtotal>$${this.formatCurrency(item.price_unit * item.quantity)}</p>
          </div>

          <button
            type="button"
            data-index="${index}"
            data-action="click->order-form#removeItem"
            class="w-8 h-8 flex items-center justify-center text-red-600 hover:bg-red-50 rounded-lg transition-colors flex-shrink-0"
            title="Eliminar"
          >
            ✕
          </button>
        </div>
      </div>
    `).join('')

    this.itemsTarget.innerHTML = html
  }

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

    this.updateSubmitButton()
  }

  updateSubmitButton() {
    if (!this.hasSubmitButtonTarget) return

    const customerSelect = this.element.querySelector('select[name="order[customer_id]"]')
    const customerValid = !!customerSelect && customerSelect.value !== ""

    const paperNumberInput = this.element.querySelector('input[name="paper_number"]')
    const paperNumberValid = !!paperNumberInput && paperNumberInput.value.trim() !== ""

    const disabled = this.items.length === 0 || !customerValid || !paperNumberValid
    this.submitButtonTarget.disabled = disabled
    if (disabled) {
      this.submitButtonTarget.classList.add("opacity-50", "cursor-not-allowed")
    } else {
      this.submitButtonTarget.classList.remove("opacity-50", "cursor-not-allowed")
    }
  }

  formatCurrency(amount) {
    return new Intl.NumberFormat('es-AR', {
      minimumFractionDigits: 0,
      maximumFractionDigits: 0
    }).format(amount)
  }
}
