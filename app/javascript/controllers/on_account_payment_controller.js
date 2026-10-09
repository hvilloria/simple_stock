import { Controller } from "@hotwired/stimulus"

// Drives the on_account collect form. Caja enters what the customer hands
// over, per method; the summary shows how far that lowers the debt. With a
// cash-only discount the cash is grossed up by the discount and rounded to the
// peso, and the exact amount that settles the balance settles it. Cash above
// that amount also settles it and is shown as overpaid. Mirrors
// Payments::CollectOnAccount, which has the last word.
export default class extends Controller {
  static targets = [
    "discount", "discountHelper",
    "tenderRows", "tenderRow", "tenderMethod", "tenderAmount", "settleAllButton",
    "receivedLine", "discountRow", "discountLabel", "discountLine",
    "resultRows", "settledLine", "balanceAfter", "overpaidRow", "overpaidLine",
    "excessNotice", "confirmedOverpaid", "submitButton", "methodHint", "roundingRow", "roundingLine"
  ]
  static values = { balance: Number, pendingDelivery: Boolean }

  connect() {
    this._tenderIdx = this.tenderRowTargets.length
    this.recalculate()
  }

  recalculate() {
    const hasNonCash = this._readTenders().some(t => t.method && t.method !== "cash")
    this.discountTarget.disabled = hasNonCash
    if (hasNonCash) this.discountTarget.value = "0"
    this.discountHelperTarget.classList.toggle("hidden", !hasNonCash)

    const discount = this._discount()
    const tenders = this._readTenders()
    const received = tenders.reduce((sum, t) => sum + t.amount, 0)
    const settleAll = this._settleAllCash(discount)
    const overpaid = this._overpaid(tenders, settleAll)
    const rounding = this._rounding(received, discount, settleAll)
    const settled = this._settled(received, discount, settleAll, overpaid, rounding)
    const excess = settled > this.balanceValue + 0.001

    this.settleAllButtonTarget.textContent = `Saldar todo: cobrar ${this.format(settleAll)}`
    this.receivedLineTarget.textContent = this.format(received)
    this.discountRowTarget.hidden = discount === 0 || excess
    this.discountLabelTarget.textContent = `Descuento ${discount}% en efectivo`
    this.discountLineTarget.textContent = this.format(settled - received + overpaid - rounding)
    this.roundingRowTarget.hidden = rounding === 0 || excess
    this.roundingLineTarget.textContent = this.format(rounding)
    this.settledLineTarget.textContent = this.format(settled)
    this.balanceAfterTarget.textContent = this.format(this.balanceValue - settled)
    this.overpaidRowTarget.hidden = overpaid === 0
    this.overpaidLineTarget.textContent = `+${this.format(overpaid)}`

    this.resultRowsTarget.hidden = excess
    this.excessNoticeTarget.hidden = !excess
    const withDiscount = discount > 0 ? ` con ${discount}%` : ""
    this.excessNoticeTarget.textContent =
      `Es más de lo que debe. Para saldar todo${withDiscount} corresponde cobrar ${this.format(settleAll)}`

    const missingMethod = tenders.some(t => t.amount > 0 && !t.method)
    this.methodHintTarget.hidden = !missingMethod
    this.submitButtonTarget.disabled = received <= 0 || excess || missingMethod
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
    const select = row.querySelector("select")
    select.name = `tenders[${idx}][payment_method]`
    select.selectedIndex = 0
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
    const discount = this._discount()
    const tenders = this._readTenders()
    const received = tenders.reduce((sum, t) => sum + t.amount, 0)
    const settleAll = this._settleAllCash(discount)
    const overpaid = this._overpaid(tenders, settleAll)
    const settled = this._settled(received, discount, settleAll, overpaid, this._rounding(received, discount, settleAll))

    this.confirmedOverpaidTarget.value = overpaid > 0 ? this._fmtPlain(overpaid) : "0"

    const messages = []
    if (overpaid > 0) messages.push(`Vas a cobrar ${this.format(overpaid)} de más en efectivo. ¿Confirmás?`)
    if (this.balanceValue - settled <= 0 && this.pendingDeliveryValue) {
      messages.push("La operación queda pagada pero faltan productos por entregar. ¿Confirmar?")
    }
    if (messages.length > 0 && !window.confirm(messages.join("\n"))) event.preventDefault()
  }

  _discount() {
    return parseInt(this.discountTarget.value, 10) || 0
  }

  // In integer cents, rounding half-up like the server.
  _settleAllCash(discount) {
    return Math.round(Math.round(this.balanceValue * 100) * (100 - discount) / 100) / 100
  }

  _overpaid(tenders, settleAll) {
    const received = tenders.reduce((sum, t) => sum + t.amount, 0)
    const cash = tenders.filter(t => t.method === "cash").reduce((sum, t) => sum + t.amount, 0)
    const extra = +(received - settleAll).toFixed(2)
    return extra >= 0.01 && extra <= cash + 0.001 ? extra : 0
  }

  // Mirrors Payments::CollectOnAccount#rounded_down?: with a discount, cash
  // down to the hundred below the settle amount still settles the balance.
  _rounding(received, discount, settleAll) {
    if (discount === 0) return 0
    const floor = Math.floor(settleAll / 100) * 100
    return floor > 0 && received >= floor && received < settleAll - 0.005 ? +(settleAll - received).toFixed(2) : 0
  }

  _settled(received, discount, settleAll, overpaid, rounding) {
    if (Math.abs(received - settleAll) < 0.005 || overpaid > 0 || rounding > 0) return this.balanceValue
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
