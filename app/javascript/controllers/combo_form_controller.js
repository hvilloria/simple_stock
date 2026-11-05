import { Controller } from "@hotwired/stimulus"
import { escapeHtml } from "helpers/html_escape"

// Combo parts and price. While the price has not been typed by hand it
// follows the sum of the parts.
export default class extends Controller {
  static targets = ["rows", "empty", "sum", "price", "hint"]
  static values = { items: Array, editable: Boolean, priceTouched: Boolean }

  connect() {
    this.items = this.itemsValue.map(item => ({
      ...item, price_unit: Number(item.price_unit), quantity: Number(item.quantity)
    }))
    this.render()
  }

  addProduct(event) {
    const product = event.detail.product
    const existing = this.items.find(item => item.id === product.id)

    if (existing) {
      existing.quantity += 1
    } else {
      this.items.push({
        id: product.id, sku: product.sku, name: product.name, brand: product.brand,
        price_unit: Number(product.price_unit), quantity: 1
      })
    }
    this.render()
  }

  removeItem(event) {
    this.items.splice(parseInt(event.currentTarget.dataset.index), 1)
    this.render()
  }

  updateQuantity(event) {
    const item = this.items[parseInt(event.currentTarget.dataset.index)]
    item.quantity = Math.max(parseInt(event.currentTarget.value) || 0, 0)
    this.refreshTotals()
  }

  priceTyped() {
    this.priceTouchedValue = true
    this.updateHint()
  }

  render() {
    this.rowsTarget.innerHTML = this.items.map((item, index) => this.rowHtml(item, index)).join("")
    this.emptyTarget.hidden = this.items.length > 0
    this.refreshTotals()
  }

  refreshTotals() {
    const sum = this.sum()
    this.sumTarget.textContent = `$${this.formatDisplay(sum)}`
    this.rowsTarget.querySelectorAll("[data-subtotal-index]").forEach(cell => {
      const item = this.items[parseInt(cell.dataset.subtotalIndex)]
      cell.textContent = `$${this.formatDisplay(item.price_unit * item.quantity)}`
    })

    if (!this.priceTouchedValue) this.priceTarget.value = sum > 0 ? this.formatAmount(sum) : ""
    this.updateHint()
  }

  updateHint() {
    const price = this.parseAmount(this.priceTarget.value)
    const difference = this.sum() - price
    const show = price > 0 && difference > 0

    this.hintTarget.hidden = !show
    this.hintTarget.textContent = show ? `$${this.formatDisplay(difference)} menos que comprar las piezas por separado` : ""
  }

  sum() {
    return this.items.reduce((total, item) => total + item.price_unit * item.quantity, 0)
  }

  rowHtml(item, index) {
    const sku = escapeHtml(item.sku)
    const name = escapeHtml(item.name) + (item.brand ? ` · ${escapeHtml(item.brand)}` : "")
    const quantity = this.editableValue
      ? `<input type="number" name="components[][quantity]" min="1" step="1" value="${item.quantity}"
           aria-label="Cantidad de ${sku}" data-index="${index}" data-action="input->combo-form#updateQuantity"
           class="w-20 px-2 py-1.5 border border-slate-300 rounded-lg text-center">`
      : `<span class="text-slate-900">${item.quantity}</span>`

    return `
      <tr class="border-b border-slate-100 last:border-b-0">
        <td class="py-3 pr-3">
          <p class="font-mono text-xs font-semibold text-slate-500">${sku}</p>
          <p class="text-slate-900">${name}</p>
          ${this.editableValue ? `<input type="hidden" name="components[][product_id]" value="${item.id}">` : ""}
        </td>
        <td class="py-3 text-center">${quantity}</td>
        <td class="py-3 text-right text-slate-700">$${this.formatDisplay(item.price_unit)}</td>
        <td class="py-3 text-right font-medium text-slate-900" data-subtotal-index="${index}"></td>
        ${this.editableValue ? `
          <td class="py-3 pl-3 text-right">
            <button type="button" aria-label="Quitar ${sku}" data-index="${index}" data-action="combo-form#removeItem"
                    class="text-slate-400 hover:text-slate-700">✕</button>
          </td>` : ""}
      </tr>
    `
  }

  // AR currency format to number: "200.000,67" -> 200000.67
  parseAmount(value) {
    if (!value) return 0
    return parseFloat(value.replace(/\./g, "").replace(/,/g, ".")) || 0
  }

  // Number to AR currency format, matching currency-input#format so the
  // prefilled value round-trips: 200000.67 -> "200.000,67"
  formatAmount(value) {
    return new Intl.NumberFormat("es-AR", {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    }).format(value || 0)
  }

  formatDisplay(value) {
    return new Intl.NumberFormat("es-AR", { maximumFractionDigits: 2 }).format(value || 0)
  }
}
