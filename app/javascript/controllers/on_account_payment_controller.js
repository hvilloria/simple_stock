import { Controller } from "@hotwired/stimulus"
import { roundToNearestHundred } from "helpers/cash_rounding"

// Drives the on_account collect form: amount-to-settle + per-event cash-only
// discount, split across one or more tenders. A single tender always covers the
// whole cash to collect, so it stays in sync and read-only; from two rows on,
// the cashier splits the amounts and the sum must match.
export default class extends Controller {
  static targets = [
    "amount", "discount", "discountHelper",
    "tenderRows", "tenderRow", "tenderMethod", "tenderAmount",
    "settleLine", "discountLine", "cashToCollect", "paidLine", "diffLine",
    "balanceAfter", "submitButton"
  ]
  static values = { balance: Number, pendingDelivery: Boolean }

  connect() {
    this._tenderIdx = this.tenderRowTargets.length
    this.recalculate()
  }

  recalculate() {
    const amount     = this.parse(this.amountTarget.value)
    const single     = this.tenderRowTargets.length === 1
    const hasNonCash = this._readTenders().some(t => t.method !== "cash")

    if (hasNonCash) {
      this.discountTarget.value = "0"
      this.discountTarget.disabled = true
      this.discountHelperTarget.classList.remove("hidden")
    } else {
      this.discountTarget.disabled = false
      this.discountHelperTarget.classList.add("hidden")
    }

    const discount = parseInt(this.discountTarget.value, 10) || 0
    const cashRaw = amount - Math.round(amount * discount) / 100
    // Discounted cash collections round to the nearest hundred (matches backend).
    const cash = discount > 0 ? roundToNearestHundred(cashRaw) : cashRaw
    // The discount shown is always the exact nominal percentage — never rounded.
    // Only the cash to collect (the total/result) gets the hundred rounding.
    const discountValue = discount > 0 ? amount * discount / 100 : 0

    this._syncTenderInputs(single, cash)

    const paid = this._readTenders().reduce((sum, t) => sum + t.amount, 0)
    const diff = +(cash - paid).toFixed(2)

    this.settleLineTarget.textContent = this.format(amount)
    this.discountLineTarget.textContent = `−${this.format(discountValue)}`
    this.cashToCollectTarget.textContent = this.format(cash)
    this.paidLineTarget.textContent = this.format(paid)
    this.diffLineTarget.textContent = this.format(diff)
    this.balanceAfterTarget.textContent = this.format(this.balanceValue - amount)

    const settled = Math.abs(diff) < 0.01
    this.diffLineTarget.classList.toggle("text-emerald-600", settled)
    this.diffLineTarget.classList.toggle("text-red-600", !settled)
    this.submitButtonTarget.disabled = !settled
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
    const amount = this.parse(this.amountTarget.value)
    const settlesNow = (this.balanceValue - amount) <= 0
    if (settlesNow && this.pendingDeliveryValue) {
      if (!window.confirm("La operación queda pagada pero faltan productos por entregar. ¿Confirmar?")) {
        event.preventDefault()
      }
    }
  }

  // With one tender there is nothing to split: mirror the cash to collect and
  // lock the field. With two or more, every row becomes editable.
  _syncTenderInputs(single, cash) {
    this.tenderAmountTargets.forEach((input, index) => {
      input.readOnly = single
      input.classList.toggle("bg-slate-50", single)
      input.classList.toggle("text-slate-500", single)
      if (single && index === 0) input.value = this._fmtPlain(cash)
    })
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
