import { Controller } from "@hotwired/stimulus"
import { roundToNearestHundred } from "helpers/cash_rounding"

// Drives the on_account collect form. Caja enters what the customer hands
// over, per method; the summary shows how far that lowers the debt. With a
// cash-only discount the cash is grossed up by the discount and rounded to the
// peso, and the exact amount that settles the balance settles it. Mirrors
// Payments::CollectOnAccount, which has the last word.
export default class extends Controller {
  static targets = [
    "discount", "discountHelper",
    "tenderRows", "tenderRow", "tenderMethod", "tenderAmount", "settleAllButton",
    "receivedLine", "discountRow", "discountLabel", "discountLine",
    "resultRows", "settledLine", "balanceAfter", "excessNotice", "submitButton"
  ]
  static values = { balance: Number, pendingDelivery: Boolean }

  connect() {
    this._tenderIdx = this.tenderRowTargets.length
    this.recalculate()
  }

  recalculate() {
    const hasNonCash = this._readTenders().some(t => t.method !== "cash")
    this.discountTarget.disabled = hasNonCash
    if (hasNonCash) this.discountTarget.value = "0"
    this.discountHelperTarget.classList.toggle("hidden", !hasNonCash)

    const discount = this._discount()
    const received = this._readTenders().reduce((sum, t) => sum + t.amount, 0)
    const settleAll = this._settleAllCash(discount)
    const settled = this._settled(received, discount, settleAll)
    const excess = settled > this.balanceValue + 0.001

    this.settleAllButtonTarget.textContent = `Saldar todo: cobrar ${this.format(settleAll)}`
    this.receivedLineTarget.textContent = this.format(received)
    this.discountRowTarget.hidden = discount === 0 || excess
    this.discountLabelTarget.textContent = `Descuento ${discount}% en efectivo`
    this.discountLineTarget.textContent = this.format(settled - received)
    this.settledLineTarget.textContent = this.format(settled)
    this.balanceAfterTarget.textContent = this.format(this.balanceValue - settled)

    this.resultRowsTarget.hidden = excess
    this.excessNoticeTarget.hidden = !excess
    const withDiscount = discount > 0 ? ` con ${discount}%` : ""
    this.excessNoticeTarget.textContent =
      `Es más de lo que debe. Para saldar todo${withDiscount} corresponde cobrar ${this.format(settleAll)}`

    this.submitButtonTarget.disabled = received <= 0 || excess
  }

  settleAll(event) {
    event.preventDefault()
    const first = this.tenderAmountTargets[0]
    first.value = this._fmtPlain(this._settleAllCash(this._discount()))
    this.recalculate()
  }

  addTender(event) {
    event.preventDefault()
    const idx = this._tenderIdx++
    const row = this.tenderRowTargets[0].cloneNode(true)
    row.querySelector("select").name = `tenders[${idx}][payment_method]`
    const input = row.querySelector("input")
    input.name = `tenders[${idx}][amount]`
    input.value = ""
    this.tenderRowsTarget.appendChild(row)
    this.recalculate()
  }

  removeTender(event) {
    event.preventDefault()
    if (this.tenderRowTargets.length <= 1) return
    event.currentTarget.closest("[data-on-account-payment-target='tenderRow']").remove()
    this.recalculate()
  }

  confirmSettle(event) {
    const received = this._readTenders().reduce((sum, t) => sum + t.amount, 0)
    const discount = this._discount()
    const settled = this._settled(received, discount, this._settleAllCash(discount))
    if (this.balanceValue - settled <= 0 && this.pendingDeliveryValue) {
      if (!window.confirm("La operación queda pagada pero faltan productos por entregar. ¿Confirmar?")) {
        event.preventDefault()
      }
    }
  }

  _discount() {
    return parseInt(this.discountTarget.value, 10) || 0
  }

  _settleAllCash(discount) {
    if (discount === 0) return this.balanceValue
    return Math.min(
      roundToNearestHundred(this.balanceValue * (100 - discount) / 100),
      this.balanceValue
    )
  }

  _settled(received, discount, settleAll) {
    if (Math.abs(received - settleAll) < 0.005) return this.balanceValue
    if (discount === 0) return received
    return Math.round(received * 100 / (100 - discount))
  }

  _readTenders() {
    return this.tenderRowTargets.map(row => ({
      method: row.querySelector("select").value,
      amount: this.parse(row.querySelector("input").value)
    }))
  }

  parse(value) {
    return parseFloat(String(value).replace(/\./g, "").replace(",", ".")) || 0
  }

  format(n) {
    return n.toLocaleString("es-AR", { style: "currency", currency: "ARS" })
  }

  _fmtPlain(n) {
    return new Intl.NumberFormat("es-AR", { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
  }
}
