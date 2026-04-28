import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "items", "count", "createButton", "backdrop"]

  connect() {
    this.cartItems = []
    this.renderPanel()
    this._escHandler = (e) => { if (e.key === "Escape") this.hidePanel() }
    document.addEventListener("keydown", this._escHandler)
  }

  disconnect() {
    document.removeEventListener("keydown", this._escHandler)
  }

  addItem(event) {
    const product = JSON.parse(event.currentTarget.dataset.cartProduct)
    const existing = this.cartItems.find(i => i.id === product.id)
    if (existing) {
      existing.quantity += 1
    } else {
      this.cartItems.push({ ...product, quantity: 1 })
    }
    this.renderPanel()
    this.updateCount()
  }

  removeItem(event) {
    const index = parseInt(event.currentTarget.dataset.cartIndex)
    this.cartItems.splice(index, 1)
    this.renderPanel()
    this.updateCount()
    if (this.cartItems.length === 0) this.hidePanel()
  }

  updateQuantity(event) {
    const index = parseInt(event.currentTarget.dataset.cartIndex)
    const value = parseInt(event.currentTarget.value)
    if (isNaN(value) || value < 1) {
      event.currentTarget.value = this.cartItems[index].quantity
      return
    }
    this.cartItems[index].quantity = value
    this.updateCount()
    this.updateCreateButton()
  }

  togglePanel() {
    if (this.panelTarget.classList.contains("hidden")) {
      this.showPanel()
    } else {
      this.hidePanel()
    }
  }

  showPanel() {
    this.backdropTarget.classList.remove("hidden")
    this.panelTarget.classList.remove("hidden")
  }

  hidePanel() {
    this.backdropTarget.classList.add("hidden")
    this.panelTarget.classList.add("hidden")
  }

  renderPanel() {
    if (this.cartItems.length === 0) {
      this.itemsTarget.innerHTML = `
        <p class="text-sm text-slate-500 text-center py-6">No hay productos en el carrito.</p>
      `
      this.updateCreateButton()
      return
    }

    this.itemsTarget.innerHTML = this.cartItems.map((item, index) => `
      <div class="flex items-center gap-3 py-3 border-b border-slate-100 last:border-0">
        <div class="flex-1 min-w-0">
          <p class="text-sm font-semibold text-slate-900 truncate">${item.name}</p>
          <p class="text-xs text-slate-500">${item.sku} · Stock: ${item.current_stock}</p>
        </div>
        <input
          type="number"
          value="${item.quantity}"
          min="1"
          class="w-16 px-2 py-1 text-sm border border-slate-300 rounded-lg text-center"
          data-action="change->cart#updateQuantity"
          data-cart-index="${index}"
        />
        <button
          type="button"
          class="text-slate-400 hover:text-red-500 transition-colors"
          data-action="click->cart#removeItem"
          data-cart-index="${index}"
        >✕</button>
      </div>
    `).join("")

    this.updateCreateButton()
  }

  updateCount() {
    const total = this.cartItems.reduce((sum, i) => sum + i.quantity, 0)
    this.countTarget.textContent = total
    this.countTarget.classList.toggle("hidden", total === 0)
  }

  updateCreateButton() {
    if (this.cartItems.length === 0) {
      this.createButtonTarget.classList.add("opacity-50", "pointer-events-none")
    } else {
      this.createButtonTarget.classList.remove("opacity-50", "pointer-events-none")
      this.createButtonTarget.href = this.buildUrl()
    }
  }

  buildUrl() {
    const params = this.cartItems.flatMap(item => [
      `purchase_items[][product_id]=${item.id}`,
      `purchase_items[][quantity]=${item.quantity}`
    ]).join("&")
    return `/web/orders/new?${params}`
  }
}
