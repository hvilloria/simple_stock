import { Controller } from "@hotwired/stimulus"

// The Productos card of the invoice form: keeps the lines, renders them with
// the hidden inputs the server reads, and tells the form what changed.
export default class extends Controller {
  static targets = ["lines", "counter"]
  static values = { initialItems: { type: Array, default: [] } }

  connect() {
    const checked = document.querySelector('input[name="currency"]:checked')
    this.currency = checked && checked.value === "USD" ? "US$" : "$"
    this.lines = this.initialItemsValue.map(item => ({
      product_id: item.product_id,
      sku: item.sku,
      name: item.name,
      brand: item.brand,
      quantity: parseInt(item.quantity) || 0,
      unit_cost: item.unit_cost === "" || item.unit_cost === null || item.unit_cost === undefined
        ? null
        : this.parseAmount(String(item.unit_cost))
    }))
    this.render()
    this.notify()
  }

  addProduct(event) {
    const product = event.detail.product
    this.lines.push({
      product_id: product.id, sku: product.sku, name: product.name, brand: product.brand,
      quantity: 1, unit_cost: null
    })
    this.render()
    this.notify()
    const costInputs = this.linesTarget.querySelectorAll("[data-cost]")
    costInputs[costInputs.length - 1]?.focus()
  }

  remove(event) {
    this.lines.splice(this.index(event), 1)
    this.render()
    this.notify()
  }

  updateQuantity(event) {
    const i = this.index(event)
    this.lines[i].quantity = parseInt(event.currentTarget.value) || 0
    this.refreshRow(i)
    this.notify()
  }

  updateCost(event) {
    const i = this.index(event)
    const raw = event.currentTarget.value.trim()
    this.lines[i].unit_cost = raw === "" ? null : this.parseAmount(raw)
    this.refreshRow(i)
    this.notify()
  }

  // A blank cost reads as zero once the operator leaves the field, so the
  // zero is on screen before the confirmation asks about it.
  settleCost(event) {
    const i = this.index(event)
    if (this.lines[i].unit_cost !== null) return
    this.lines[i].unit_cost = 0
    event.currentTarget.value = this.formatAmount(0)
    this.refreshRow(i)
    this.notify()
  }

  currencyChanged(event) {
    this.currency = event.detail.currency === "USD" ? "US$" : "$"
    this.element.querySelectorAll("[data-currency]").forEach(el => { el.textContent = this.currency })
  }

  index(event) { return parseInt(event.currentTarget.dataset.index) }

  complete(line) { return Boolean(line.product_id) && line.quantity > 0 }

  cost(line) { return line.unit_cost === null ? 0 : line.unit_cost }

  subtotal(line) { return this.complete(line) ? this.cost(line) * line.quantity : 0 }

  parseAmount(value) {
    if (!value) return 0
    return parseFloat(value.replace(/\./g, "").replace(/,/g, ".")) || 0
  }

  formatAmount(value) {
    return new Intl.NumberFormat("es-AR", { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(value || 0)
  }

  notify() {
    const complete = this.lines.filter(line => this.complete(line))
    const detail = {
      lines: complete.map(line => ({ product_id: line.product_id, name: line.name, quantity: line.quantity, unit_cost: this.cost(line) })),
      total: complete.reduce((sum, line) => sum + this.subtotal(line), 0),
      units: complete.reduce((sum, line) => sum + line.quantity, 0),
      products: complete.length,
      zeroCostLines: complete.filter(line => this.cost(line) === 0).map(line => ({ name: line.name, quantity: line.quantity }))
    }
    this.counterTarget.textContent = complete.length
      ? `${complete.length} ${complete.length === 1 ? "producto" : "productos"} · ${detail.units} ${detail.units === 1 ? "unidad" : "unidades"}`
      : "opcional"
    this.element.dispatchEvent(new CustomEvent("lines-changed", { detail, bubbles: true }))
  }

  refreshRow(i) {
    const row = this.linesTarget.querySelector(`[data-line-index="${i}"]`)
    if (!row) return
    const line = this.lines[i]
    row.classList.toggle("opacity-50", !this.complete(line))
    row.querySelector("[data-subtotal]").textContent = this.complete(line) ? this.formatAmount(this.subtotal(line)) : "—"
    row.querySelector('input[data-field="quantity"]').value = line.quantity
    row.querySelector('input[data-field="unit_cost"]').value = line.unit_cost === null ? "" : this.formatAmount(line.unit_cost)
    this.linesTarget.querySelector("[data-total]").textContent = this.formatAmount(
      this.lines.reduce((sum, l) => sum + this.subtotal(l), 0)
    )
  }

  render() {
    if (this.lines.length === 0) {
      this.linesTarget.innerHTML = `
        <div class="rounded-lg border border-dashed border-slate-300 px-6 py-8 text-center">
          <p class="text-sm font-medium text-slate-700">No hay productos cargados.</p>
          <p class="mt-1 text-xs text-slate-500">Buscá y agregá si querés que esta factura sume stock.</p>
        </div>
      `
      return
    }

    const rows = this.lines.map((line, i) => `
      <tr data-line-index="${i}" class="${this.complete(line) ? "" : "opacity-50"}">
        <td class="py-2 pr-3">
          <span class="font-mono text-xs text-slate-500">${line.sku}</span><br>
          <span class="text-slate-900">${line.name}</span>${line.brand ? ` <span class="text-slate-400">· ${line.brand}</span>` : ""}
          <input type="hidden" name="items[${i}][product_id]" value="${line.product_id}">
          <input type="hidden" name="items[${i}][sku]" value="${line.sku}">
          <input type="hidden" name="items[${i}][name]" value="${line.name}">
          <input type="hidden" name="items[${i}][brand]" value="${line.brand || ""}">
          <input type="hidden" name="items[${i}][quantity]" value="${line.quantity}" data-field="quantity">
          <input type="hidden" name="items[${i}][unit_cost]" value="${line.unit_cost === null ? "" : this.formatAmount(line.unit_cost)}" data-field="unit_cost">
        </td>
        <td class="py-2 text-right">
          <input type="number" min="0" value="${line.quantity}" data-index="${i}"
                 data-action="input->invoice-lines#updateQuantity"
                 class="w-20 rounded-lg border border-slate-300 px-2 py-1.5 text-right">
        </td>
        <td class="py-2 text-right">
          <input type="text" value="${line.unit_cost === null ? "" : this.formatAmount(line.unit_cost)}" data-index="${i}" data-cost
                 data-controller="currency-input"
                 data-action="input->invoice-lines#updateCost blur->invoice-lines#settleCost blur->currency-input#format focus->currency-input#unformat"
                 class="w-28 rounded-lg border border-slate-300 px-2 py-1.5 text-right">
        </td>
        <td class="py-2 text-right tabular-nums" data-subtotal>${this.complete(line) ? this.formatAmount(this.subtotal(line)) : "—"}</td>
        <td class="py-2 text-right">
          <button type="button" data-index="${i}" data-action="click->invoice-lines#remove"
                  class="h-8 w-8 rounded-lg text-slate-400 hover:bg-slate-100 hover:text-slate-700" title="Quitar">✕</button>
        </td>
      </tr>
    `).join("")

    this.linesTarget.innerHTML = `
      <table class="w-full text-sm">
        <thead class="text-xs uppercase tracking-wider text-slate-500">
          <tr>
            <th class="py-2 text-left font-medium">Producto</th>
            <th class="py-2 text-right font-medium">Cantidad</th>
            <th class="py-2 text-right font-medium">Costo unit. (<span data-currency>${this.currency}</span>)</th>
            <th class="py-2 text-right font-medium">Subtotal</th>
            <th class="py-2"></th>
          </tr>
        </thead>
        <tbody class="divide-y divide-slate-100">${rows}</tbody>
        <tfoot class="border-t-2 border-slate-200 font-semibold">
          <tr>
            <td class="py-2" colspan="3">Total</td>
            <td class="py-2 text-right tabular-nums" data-total>${this.formatAmount(this.lines.reduce((sum, l) => sum + this.subtotal(l), 0))}</td>
            <td></td>
          </tr>
        </tfoot>
      </table>
    `
  }
}
