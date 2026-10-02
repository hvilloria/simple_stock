import { Controller } from "@hotwired/stimulus"
import { roundToNearestHundred } from "helpers/cash_rounding"

// Drives the cashier cobro form:
//   - keeps the live summary in sync with discount + tenders
//   - enforces "discount only if 100% cash" rule on the front (back also enforces)
export default class extends Controller {
  static targets = [
    "discountSelect", "discountHelper",
    "tenderRows", "tenderRow", "tenderMethod", "tenderAmount",
    "summaryDiscount", "summaryTotal", "summaryPaid", "summaryDiff",
    "submitButton"
  ]

  static values = {
    originalTotal: Number
  }

  connect() {
    this._tenderIdx = this.tenderRowTargets.length
    this.recalc()
  }

  // Selecting a discount: only the all-cash rule blocks it. If a single tender
  // is present, auto-fill it with the discounted total so the cashier doesn't
  // have to retype the amount.
  discountChanged() {
    const discount = parseInt(this.discountSelectTarget.value, 10) || 0

    // Auto-fill a single tender with the discounted total so the cashier
    // doesn't have to retype the amount after picking a discount.
    if (discount > 0 && this.tenderRowTargets.length === 1) {
      const finalTotal = this._finalTotal(discount)
      this.tenderRowTargets[0].querySelector("input").value = this._fmtPlain(finalTotal)
    }

    this.recalc()
  }

  recalc() {
    const tenders    = this._readTenders()
    const hasNonCash = tenders.some(t => t.method !== "cash")
    let   discount   = parseInt(this.discountSelectTarget.value, 10) || 0

    // Cash-only discount rule: a non-cash tender forces the discount back to 0.
    if (discount > 0 && hasNonCash) {
      this.discountSelectTarget.value = "0"
      discount = 0
    }
    this.discountHelperTarget.classList.toggle("text-red-600", hasNonCash)

    const finalTotal = this._finalTotal(discount)
    const paidSum    = tenders.reduce((s, t) => s + t.amount, 0)
    const diff       = +(finalTotal - paidSum).toFixed(2)

    // The discount shown is always the exact nominal amount (never rounded).
    // Rounding applies only to the total to collect (the result), via _finalTotal.
    const nominalDiscount = discount > 0 ? this.originalTotalValue * discount / 100 : 0
    this.summaryDiscountTarget.textContent = `−${this._fmt(nominalDiscount)}`
    this.summaryTotalTarget.textContent    = this._fmt(finalTotal)
    this.summaryPaidTarget.textContent     = this._fmt(paidSum)
    this.summaryDiffTarget.textContent     = this._fmt(diff)
    const settled = Math.abs(diff) < 0.01
    this.summaryDiffTarget.classList.toggle("text-emerald-600", settled)
    this.summaryDiffTarget.classList.toggle("text-red-600", !settled)
    this.submitButtonTarget.disabled       = Math.abs(diff) >= 0.01
  }

  addTender(event) {
    event.preventDefault()
    const idx = this._tenderIdx++
    const row = this.tenderRowTargets[0].cloneNode(true)
    row.querySelector("select").name = `tenders[${idx}][payment_method]`
    const input = row.querySelector("input")
    input.name  = `tenders[${idx}][amount]`
    input.value = ""
    this.tenderRowsTarget.appendChild(row)
    this.recalc()
  }

  removeTender(event) {
    event.preventDefault()
    if (this.tenderRowTargets.length <= 1) return
    event.currentTarget.closest("[data-sale-note-payment-target='tenderRow']").remove()
    this.recalc()
  }

  // Discounted cash totals round to the nearest hundred (matches backend).
  // No discount: the exact two-decimal total.
  _finalTotal(discount) {
    const raw = this.originalTotalValue * (1 - discount / 100)
    return discount > 0 ? roundToNearestHundred(raw) : +raw.toFixed(2)
  }

  _readTenders() {
    return this.tenderRowTargets.map(row => {
      const method = row.querySelector("select").value
      const raw    = row.querySelector("input").value.replace(/\./g, "").replace(/,/g, ".")
      const amount = parseFloat(raw) || 0
      return { method, amount }
    })
  }

  _fmt(n) {
    return new Intl.NumberFormat("es-AR", { style: "currency", currency: "ARS", minimumFractionDigits: 2 }).format(n)
  }

  _fmtPlain(n) {
    return new Intl.NumberFormat("es-AR", { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
  }
}
