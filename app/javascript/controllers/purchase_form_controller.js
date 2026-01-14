import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["items", "total", "totalArs", "itemCount", "totalQuantity", "currencyUsd", "currencyArs", "exchangeRateField", "submitButton"]

  connect() {
    this.items = []
    this.currency = 'USD'
    this.exchangeRate = null
    this.updateSummary()
    this.toggleExchangeRate()
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
        unit_cost: product.cost_unit || 0,
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
    
    if (newQuantity > 0) {
      debugger
      this.items[index].quantity = newQuantity
      debugger
      this.updateItemSubtotal(index)
      this.updateSummary()
    }
  }

  updateCost(event) {
    const index = parseInt(event.currentTarget.dataset.index)
    const newCost = parseFloat(event.currentTarget.value)
    
    if (newCost >= 0) {
      this.items[index].unit_cost = newCost
      this.updateItemSubtotal(index)
      this.updateSummary()
    }
  }

  updateItemSubtotal(index) {
    const item = this.items[index]
    const currencySymbol = this.currency === 'USD' ? 'USD' : 'ARS'
    const subtotal = item.unit_cost * item.quantity
    
    // Actualizar los hidden inputs y el subtotal display
    const itemElements = this.itemsTarget.children
    if (itemElements[index]) {
      const hiddenQuantity = itemElements[index].querySelector('input[name="purchase_items[][quantity]"]')
      const hiddenCost = itemElements[index].querySelector('input[name="purchase_items[][unit_cost]"]')
      
      // Buscar el subtotal (es el último p.text-base dentro del item)
      const subtotalDisplays = itemElements[index].querySelectorAll('p.text-base')
      const subtotalDisplay = subtotalDisplays[subtotalDisplays.length - 1]
      
      if (hiddenQuantity) hiddenQuantity.value = item.quantity
      if (hiddenCost) hiddenCost.value = item.unit_cost
      if (subtotalDisplay) {
        subtotalDisplay.textContent = `${currencySymbol} ${this.formatCurrency(subtotal)}`
      }
    }
  }

  changeCurrency(event) {
    this.currency = event.target.value
    this.toggleExchangeRate()
    this.updateAllSubtotals()
    this.updateSummary()
  }

  updateAllSubtotals() {
    this.items.forEach((item, index) => {
      this.updateItemSubtotal(index)
    })
  }

  updateExchangeRate(event) {
    this.exchangeRate = parseFloat(event.target.value) || null
    this.updateSummary()
  }

  toggleExchangeRate() {
    if (this.hasExchangeRateFieldTarget) {
      if (this.currency === 'USD') {
        this.exchangeRateFieldTarget.classList.remove('hidden')
      } else {
        this.exchangeRateFieldTarget.classList.add('hidden')
      }
    }
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

    const currencySymbol = this.currency === 'USD' ? 'USD' : 'ARS'
    debugger
    const html = this.items.map((item, index) => `
      <div class="flex items-center gap-4 p-4 border border-gray-200 rounded-xl bg-white hover:shadow-sm transition-all">
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
          <input type="hidden" name="purchase_items[][unit_cost]" value="${item.unit_cost}" />
        </div>
        
        <div class="flex items-center gap-3">
          <div class="text-right">
            <p class="text-xs text-gray-500 mb-1">Cantidad</p>
            <input 
              type="number" 
              value="${item.quantity}"
              min="1"
              data-index="${index}"
              data-action="input->purchase-form#updateQuantity"
              class="w-20 px-2 py-1.5 border border-gray-300 rounded-lg text-center font-semibold focus:ring-2 focus:ring-gray-700"
            />
          </div>
          
          <div class="text-right">
            <p class="text-xs text-gray-500 mb-1">Costo Unit.</p>
            <div class="relative">
              <span class="absolute left-2 top-1/2 -translate-y-1/2 text-xs text-gray-500">$</span>
              <input 
                type="number" 
                value="${item.unit_cost}"
                min="0"
                step="0.01"
                data-index="${index}"
                data-action="input->purchase-form#updateCost"
                class="w-28 pl-5 pr-2 py-1.5 border border-gray-300 rounded-lg text-right font-semibold focus:ring-2 focus:ring-gray-700"
              />
            </div>
          </div>
          
          <div class="text-right min-w-[120px]">
            <p class="text-xs text-gray-500 mb-1">Subtotal</p>
            <p class="text-base font-bold text-gray-900">${currencySymbol} ${this.formatCurrency(item.unit_cost * item.quantity)}</p>
          </div>
          
          <button 
            type="button"
            data-index="${index}"
            data-action="click->purchase-form#removeItem"
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
    const total = this.items.reduce((sum, item) => sum + (item.unit_cost * item.quantity), 0)
    const itemCount = this.items.length
    const totalQuantity = this.items.reduce((sum, item) => sum + item.quantity, 0)

    if (this.hasTotalTarget) {
      const currencyLabel = this.currency === 'USD' ? 'USD' : 'ARS'
      this.totalTarget.textContent = `${currencyLabel} ${this.formatCurrency(total)}`
    }

    // Mostrar conversión a ARS si es USD
    if (this.hasTotalArsTarget) {
      if (this.currency === 'USD' && this.exchangeRate && this.exchangeRate > 0) {
        const totalArs = total * this.exchangeRate
        this.totalArsTarget.innerHTML = `
          <p class="text-sm text-gray-500">≈ ARS ${this.formatCurrency(totalArs)}</p>
          <p class="text-xs text-gray-400">(TC: ${this.formatCurrency(this.exchangeRate)})</p>
        `
      } else {
        this.totalArsTarget.innerHTML = ''
      }
    }
    
    if (this.hasItemCountTarget) {
      this.itemCountTarget.textContent = `${itemCount} producto${itemCount !== 1 ? 's' : ''}`
    }

    if (this.hasTotalQuantityTarget) {
      this.totalQuantityTarget.textContent = `${totalQuantity} unidad${totalQuantity !== 1 ? 'es' : ''}`
    }

    if (this.hasSubmitButtonTarget) {
      const isValid = this.items.length > 0 && (this.currency === 'ARS' || (this.exchangeRate && this.exchangeRate > 0))
      this.submitButtonTarget.disabled = !isValid
      
      if (!isValid) {
        this.submitButtonTarget.classList.add('opacity-50', 'cursor-not-allowed')
      } else {
        this.submitButtonTarget.classList.remove('opacity-50', 'cursor-not-allowed')
      }
    }
  }

  formatCurrency(amount) {
    return new Intl.NumberFormat('es-AR', {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    }).format(amount)
  }
}

