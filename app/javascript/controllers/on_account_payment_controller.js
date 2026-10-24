import { Controller } from "@hotwired/stimulus"

// Drives the on_account collect form. A cash-only discount is that percent of
// the cash handed over; settling in cash costs what is left to pay discounted,
// minus the discount already earned, and cash above that is shown as overpaid.
// Mirrors Payments::CollectOnAccount, which has the last word.
export default class extends Controller {
  static targets = [
    "discount", "discountHelper",
    "tenderRows", "tenderRow", "tenderMethod", "tenderAmount", "settleAllButton",
    "receivedLine", "discountRow", "discountLabel", "discountLine",
    "resultRows", "remainingAfterRow", "remainingAfterLine", "earnedAfterRow", "earnedAfterLine",
    "balanceAfter", "overpaidRow", "overpaidLine",
    "excessNotice", "confirmedOverpaid", "submitButton", "methodHint", "roundingRow", "roundingLine",
    "cashToChargeRow", "cashToChargeLabel", "cashToChargeLine"
  ]
  static values = { balance: Number, remaining: Number, earned: Number, pendingDelivery: Boolean }

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
    const settlesAll = this._settlesAll(received, settleAll, overpaid, rounding)
    const settled = this._settled(received, discount, settlesAll)
    const excess = settled > this.balanceValue + 0.001
    const discountAmount = settled - received + overpaid - rounding

    const chargeCash = this._chargeCash(discount)
    this.settleAllButtonTarget.textContent = `Saldar todo: cobrar ${this.format(chargeCash)}`
    this.cashToChargeRowTarget.hidden = discount === 0
    this.cashToChargeLabelTarget.textContent = `En efectivo con ${discount}%`
    this.cashToChargeLineTarget.textContent = this.format(settleAll)
    this.receivedLineTarget.textContent = this.format(received)
    this.discountRowTarget.hidden = discount === 0 || excess
    this.discountLabelTarget.textContent =
      settlesAll ? `Descuento ${discount}% de lo que resta` : `Gana de descuento (${discount}%)`
    this.discountLineTarget.textContent = this.format(discountAmount)
    this.roundingRowTarget.hidden = rounding === 0 || excess
    this.roundingLineTarget.textContent = this.format(rounding)
    this.remainingAfterRowTarget.hidden = settlesAll
    this.remainingAfterLineTarget.textContent = this.format(this.remainingValue - received)
    const earnedAfter = this.earnedValue + discountAmount
    this.earnedAfterRowTarget.hidden = settlesAll || earnedAfter === 0
    this.earnedAfterLineTarget.textContent = `−${this.format(earnedAfter)}`
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
    first.value = this._fmtPlain(this._chargeCash(this._discount()))
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
    const settlesAll = this._settlesAll(received, settleAll, overpaid, this._rounding(received, discount, settleAll))
    const settled = this._settled(received, discount, settlesAll)

    this.confirmedOverpaidTarget.value = overpaid > 0 ? this._fmtPlain(overpaid) : "0"

    const messages = []
    if (overpaid > 0) messages.push(`Se cobrará ${this.format(overpaid)} de más en efectivo. ¿Confirmar el cobro?`)
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
    if (discount === 0) return this.balanceValue
    const cents = Math.round(Math.round(this.remainingValue * 100) * (100 - discount) / 100) -
      Math.round(this.earnedValue * 100)
    return cents > 0 ? cents / 100 : this.balanceValue
  }

  // With a discount, the settle-all cash rounded down to the hundred, which
  // the server also accepts as settling the balance.
  _chargeCash(discount) {
    const settleAll = this._settleAllCash(discount)
    if (discount === 0) return settleAll
    const floor = Math.floor(settleAll / 100) * 100
    return floor > 0 ? floor : settleAll
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

  _settlesAll(received, settleAll, overpaid, rounding) {
    return Math.abs(received - settleAll) < 0.005 || overpaid > 0 || rounding > 0
  }

  _settled(received, discount, settlesAll) {
    if (settlesAll) return this.balanceValue
    return received + Math.round(received * discount / 100)
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
