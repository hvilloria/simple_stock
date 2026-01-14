import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "results"]
  static values = { url: String }

  connect() {
    this.timeout = null
  }

  search() {
    clearTimeout(this.timeout)
    const query = this.inputTarget.value.trim()
    
    if (query.length < 2) {
      this.hideResults()
      return
    }

    this.timeout = setTimeout(() => {
      this.performSearch(query)
    }, 300)
  }

  async performSearch(query) {
    try {
      const response = await fetch(`${this.urlValue}?q=${encodeURIComponent(query)}`, {
        headers: { 'Accept': 'application/json' }
      })
      
      if (!response.ok) throw new Error('Search failed')
      
      const products = await response.json()
      this.displayResults(products)
    } catch (error) {
      console.error('Error:', error)
      this.resultsTarget.innerHTML = '<div class="px-4 py-3 text-sm text-red-600">Error al buscar productos</div>'
      this.showResults()
    }
  }

  displayResults(products) {
    if (products.length === 0) {
      this.resultsTarget.innerHTML = `
        <div class="px-4 py-3 text-sm text-gray-500 text-center">
          <p class="mb-1">🔍</p>
          <p>No se encontraron productos</p>
        </div>
      `
      this.showResults()
      return
    }

    const html = products.map(product => {
      const stockBadge = product.current_stock <= 0 
        ? '<span class="px-2 py-0.5 bg-red-100 text-red-700 text-xs rounded-full font-medium">Sin stock</span>'
        : product.current_stock < 5
        ? '<span class="px-2 py-0.5 bg-yellow-100 text-yellow-700 text-xs rounded-full font-medium">Stock bajo</span>'
        : `<span class="px-2 py-0.5 bg-green-100 text-green-700 text-xs rounded-full font-medium">Stock: ${product.current_stock}</span>`
      
      const typeBadge = product.product_type === 'oem'
        ? '<span class="px-2 py-0.5 bg-gray-100 text-gray-700 text-xs rounded-full">OEM</span>'
        : product.product_type === 'aftermarket'
        ? '<span class="px-2 py-0.5 bg-blue-100 text-blue-700 text-xs rounded-full">Aftermarket</span>'
        : ''
      
      const originText = product.origin ? `🌍 ${product.origin}` : ''

      return `
        <div 
          class="px-4 py-3 hover:bg-gray-50 cursor-pointer border-b border-gray-100 last:border-b-0 transition-colors ${product.current_stock <= 0 ? 'opacity-50' : ''}"
          data-action="click->product-search#selectProduct"
          data-product='${JSON.stringify(product)}'
        >
          <div class="flex items-center gap-3">
            <div class="w-10 h-10 rounded-lg bg-gray-100 flex items-center justify-center text-lg flex-shrink-0">
              📦
            </div>
            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-2 mb-1">
                <span class="font-mono text-xs text-gray-500 font-semibold">${product.sku}</span>
                ${stockBadge}
                ${typeBadge}
              </div>
              <p class="font-semibold text-gray-900 text-sm truncate">${product.name}</p>
              <div class="flex items-center gap-2 text-xs text-gray-600 mt-1">
                ${product.brand ? `<span>${product.brand}</span>` : ''}
                ${product.brand && originText ? '<span>•</span>' : ''}
                ${originText ? `<span>${originText}</span>` : ''}
                <span>•</span>
                <span class="font-bold text-gray-900">$${this.formatCurrency(product.price_unit)}</span>
              </div>
            </div>
          </div>
        </div>
      `
    }).join('')

    this.resultsTarget.innerHTML = html
    this.showResults()
  }

  selectProduct(event) {
    const product = JSON.parse(event.currentTarget.dataset.product)
    
    // Solo validar stock si NO estamos en un formulario de compra
    const isPurchaseForm = this.element.closest('[data-controller*="purchase-form"]')
    if (!isPurchaseForm && product.current_stock <= 0) {
      alert('Este producto no tiene stock disponible')
      return
    }

    const customEvent = new CustomEvent('product-selected', {
      detail: { product },
      bubbles: true
    })
    this.element.dispatchEvent(customEvent)

    this.inputTarget.value = ''
    this.hideResults()
  }

  showResults() {
    this.resultsTarget.classList.remove('hidden')
  }

  hideResults() {
    this.resultsTarget.classList.add('hidden')
  }

  clickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.hideResults()
    }
  }

  formatCurrency(amount) {
    return new Intl.NumberFormat('es-AR', {
      minimumFractionDigits: 0,
      maximumFractionDigits: 0
    }).format(amount)
  }
}

