import { Controller } from "@hotwired/stimulus"
import { escapeHtml } from "helpers/html_escape"

// The Productos and Totales cards of the invoice form: keeps the lines,
// renders them with the hidden inputs the server reads, totals them with the
// paper's discount and IVA, and tells the form what changed.
export default class extends Controller {
  static targets = [
    "lines", "counter", "totals", "discount", "iva",
    "subtotal", "discountLabel", "discountAmount", "ivaLabel", "ivaAmount", "grandTotal"
  ]
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

  clear() {
    if (this.lines.length === 0) return
    this.lines = []
    this.render()
    this.notify()
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

  totalsChanged() {
    this.lines.forEach((_, i) => this.refreshRow(i))
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

  // ========== DISCOUNT AND IVA ==========
  // Everything is counted in whole cents and hundredths of a percent, rounded
  // half-up at each step exactly as the server does, so the screen and the
  // registered amount never disagree.

  // Read the way the server reads it: blank takes the default, and anything
  // the server would refuse is null.
  percentage(input, fallback) {
    const raw = input.value.trim()
    if (raw === "") return fallback * 100
    const plain = raw.includes(",") ? raw.replace(/\./g, "").replace(",", ".") : raw
    if (!/^\d+(\.\d{1,2})?$/.test(plain)) return null
    const hundredths = Math.round(Number(plain) * 100)
    return hundredths <= 10000 ? hundredths : null
  }

  rates() {
    const discount = this.percentage(this.discountTarget, 0)
    const iva = this.percentage(this.ivaTarget, 21)
    return discount === null || iva === null ? null : { discount, iva }
  }

  cents(amount) { return BigInt(Math.round(amount * 100)) }

  roundDiv(numerator, denominator) { return (numerator * 2n + denominator) / (denominator * 2n) }

  finalCostCents(line, rates) {
    if (!rates) return null
    return this.roundDiv(this.cents(this.cost(line)) * BigInt(10000 - rates.discount) * BigInt(10000 + rates.iva), 100000000n)
  }

  totals(rates) {
    const subtotal = this.lines.reduce((sum, line) =>
      this.complete(line) ? sum + this.cents(this.cost(line)) * BigInt(line.quantity) : sum, 0n)
    if (!rates) return { subtotal, discount: null, iva: null, total: null }

    const discount = this.roundDiv(subtotal * BigInt(rates.discount), 10000n)
    const iva = this.roundDiv((subtotal - discount) * BigInt(rates.iva), 10000n)
    return { subtotal, discount, iva, total: subtotal - discount + iva }
  }

  pesos(cents) { return cents === null ? null : Number(cents) / 100 }

  money(cents) { return cents === null ? "—" : this.formatAmount(this.pesos(cents)) }

  percentLabel(hundredths) {
    return new Intl.NumberFormat("es-AR", { maximumFractionDigits: 2 }).format(hundredths / 100)
  }

  finalCostText(line) {
    return this.complete(line) ? this.money(this.finalCostCents(line, this.rates())) : "—"
  }

  renderTotals(shown, rates, totals) {
    this.totalsTarget.hidden = !shown
    this.totalsTarget.disabled = !shown
    this.subtotalTarget.textContent = this.money(totals.subtotal)
    this.discountLabelTarget.textContent = rates ? `Descuento ${this.percentLabel(rates.discount)}%` : "Descuento"
    this.discountAmountTarget.textContent = totals.discount === null ? "—" : `−${this.money(totals.discount)}`
    this.ivaLabelTarget.textContent = rates ? `IVA ${this.percentLabel(rates.iva)}%` : "IVA"
    this.ivaAmountTarget.textContent = totals.iva === null ? "—" : `+${this.money(totals.iva)}`
    this.grandTotalTarget.textContent = totals.total === null ? "—" : `$ ${this.money(totals.total)}`
  }

  notify() {
    const complete = this.lines.filter(line => this.complete(line))
    const rates = this.rates()
    const totals = this.totals(rates)
    this.renderTotals(complete.length > 0, rates, totals)
    const detail = {
      lines: complete.map(line => ({
        product_id: line.product_id, name: line.name, quantity: line.quantity, unit_cost: this.cost(line),
        final_cost: this.pesos(this.finalCostCents(line, rates))
      })),
      total: this.pesos(totals.total),
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
    row.querySelector("[data-final-cost]").textContent = this.finalCostText(line)
    row.querySelector('input[data-field="quantity"]').value = line.quantity
    row.querySelector('input[data-field="unit_cost"]').value = line.unit_cost === null ? "" : this.formatAmount(line.unit_cost)
  }

  render() {
    if (this.lines.length === 0) {
      this.linesTarget.innerHTML = `
        <div class="rounded-lg border border-dashed border-slate-300 px-6 py-8 text-center">
          <p class="text-sm font-medium text-slate-700">No hay productos cargados.</p>
          <p class="mt-1 text-xs text-slate-500">Agregar productos solo si esta factura debe sumar stock.</p>
        </div>
      `
      return
    }

    const rows = this.lines.map((line, i) => `
      <tr data-line-index="${i}" class="${this.complete(line) ? "" : "opacity-50"}">
        <td class="py-2 pr-3">
          <span class="font-mono text-xs text-slate-500">${escapeHtml(line.sku)}</span><br>
          <span class="text-slate-900">${escapeHtml(line.name)}</span>${line.brand ? ` <span class="text-slate-400">· ${escapeHtml(line.brand)}</span>` : ""}
          <input type="hidden" name="items[${i}][product_id]" value="${line.product_id}">
          <input type="hidden" name="items[${i}][sku]" value="${escapeHtml(line.sku)}">
          <input type="hidden" name="items[${i}][name]" value="${escapeHtml(line.name)}">
          <input type="hidden" name="items[${i}][brand]" value="${escapeHtml(line.brand)}">
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
        <td class="py-2 pl-3 text-right tabular-nums" data-subtotal>${this.complete(line) ? this.formatAmount(this.subtotal(line)) : "—"}</td>
        <td class="py-2 pl-3 text-right tabular-nums font-medium" data-final-cost>${this.finalCostText(line)}</td>
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
            <th class="py-2 text-right font-medium">Precio unit. (<span data-currency>${this.currency}</span>)</th>
            <th class="py-2 pl-3 text-right font-medium">Subtotal</th>
            <th class="py-2 pl-3 text-right font-medium whitespace-nowrap">Costo final</th>
            <th class="py-2"></th>
          </tr>
        </thead>
        <tbody class="divide-y divide-slate-100">${rows}</tbody>
      </table>
    `
  }
}
