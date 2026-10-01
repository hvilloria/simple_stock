import { Controller } from "@hotwired/stimulus"

const MAX_COUNT = 1000000

// The lines of the stock adjustment page: the admin types the counted units,
// each row shows the difference against current stock, and the form submits
// only with a reason, no blank row, and at least one change.
export default class extends Controller {
  static targets = ["lines", "counter", "note", "submit"]
  static values = { initialLines: { type: Array, default: [] } }

  connect() {
    this.lines = this.initialLinesValue.map(line => ({
      product_id: line.product_id,
      sku: line.sku,
      name: line.name,
      brand: line.brand || "",
      current_stock: parseInt(line.current_stock) || 0,
      counted: line.counted === null || line.counted === undefined ? "" : String(line.counted)
    }))
    this.render()
    this.refresh()
  }

  addProduct(event) {
    const product = event.detail.product
    let index = this.lines.findIndex(line => String(line.product_id) === String(product.id))
    if (index === -1) {
      this.lines.push({
        product_id: product.id, sku: product.sku, name: product.name, brand: product.brand || "",
        current_stock: parseInt(product.current_stock) || 0, counted: ""
      })
      index = this.lines.length - 1
      this.render()
      this.refresh()
    }
    this.linesTarget.querySelector(`input[data-index="${index}"]`)?.focus()
  }

  remove(event) {
    this.lines.splice(this.index(event), 1)
    this.render()
    this.refresh()
  }

  updateCounted(event) {
    const i = this.index(event)
    this.lines[i].counted = event.currentTarget.value.trim()
    const row = this.linesTarget.querySelector(`[data-line-index="${i}"]`)
    row.querySelector("[data-difference]").textContent = this.differenceLabel(this.lines[i])
    this.refresh()
  }

  preventEnter(event) {
    event.preventDefault()
  }

  refresh() {
    const changed = this.lines.filter(line => this.difference(line)).length
    const blank = this.lines.some(line => this.difference(line) === null)
    this.counterTarget.textContent = this.lines.length === 0
      ? "ninguno"
      : `${this.lines.length} ${this.lines.length === 1 ? "producto" : "productos"} · ${changed} con cambio`
    this.submitTarget.disabled = !(this.noteTarget.value.trim() && changed > 0 && !blank)
  }

  index(event) { return parseInt(event.currentTarget.dataset.index) }

  difference(line) {
    if (!/^\d+$/.test(line.counted)) return null
    const counted = parseInt(line.counted, 10)
    if (counted > MAX_COUNT) return null
    return counted - line.current_stock
  }

  differenceLabel(line) {
    const difference = this.difference(line)
    if (difference === null) return "—"
    if (difference === 0) return "sin cambio"
    return difference > 0 ? `+${difference}` : `−${Math.abs(difference)}`
  }

  escape(value) {
    return String(value ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c])
  }

  render() {
    if (this.lines.length === 0) {
      this.linesTarget.innerHTML = `
        <div class="rounded-lg border border-dashed border-slate-300 px-6 py-8 text-center">
          <p class="text-sm text-slate-500">Buscá un producto para agregarlo al ajuste.</p>
        </div>
      `
      return
    }

    const rows = this.lines.map((line, i) => `
      <tr data-line-index="${i}">
        <td class="py-2 pr-3 font-mono text-xs text-slate-500">
          ${this.escape(line.sku)}
          <input type="hidden" name="lines[${i}][product_id]" value="${this.escape(line.product_id)}">
        </td>
        <td class="py-2 pr-3 text-slate-900">
          ${this.escape(line.name)}${line.brand ? ` <span class="text-slate-400">· ${this.escape(line.brand)}</span>` : ""}
        </td>
        <td class="py-2 text-right tabular-nums text-slate-600">${line.current_stock}</td>
        <td class="py-2 text-right">
          <input type="number" min="0" max="${MAX_COUNT}" step="1" name="lines[${i}][counted]" value="${this.escape(line.counted)}"
                 data-index="${i}" data-action="input->stock-adjustment-lines#updateCounted"
                 aria-label="Stock real de ${this.escape(line.name)}"
                 class="w-24 rounded-lg border border-slate-300 px-2 py-1.5 text-right">
        </td>
        <td class="py-2 text-right tabular-nums text-slate-700" data-difference>${this.differenceLabel(line)}</td>
        <td class="py-2 text-right">
          <button type="button" data-index="${i}" data-action="click->stock-adjustment-lines#remove"
                  class="h-8 w-8 rounded-lg text-slate-400 hover:bg-slate-100 hover:text-slate-700" title="Quitar">✕</button>
        </td>
      </tr>
    `).join("")

    this.linesTarget.innerHTML = `
      <div class="overflow-x-auto">
        <table class="w-full text-sm">
          <thead class="text-xs uppercase tracking-wider text-slate-500">
            <tr>
              <th class="py-2 text-left font-medium">SKU</th>
              <th class="py-2 text-left font-medium">Producto</th>
              <th class="py-2 text-right font-medium">Stock actual</th>
              <th class="py-2 text-right font-medium">Stock real</th>
              <th class="py-2 text-right font-medium">Diferencia</th>
              <th class="py-2"></th>
            </tr>
          </thead>
          <tbody class="divide-y divide-slate-100">${rows}</tbody>
        </table>
      </div>
    `
  }
}
