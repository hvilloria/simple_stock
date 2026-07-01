import { Controller } from "@hotwired/stimulus"
import { roundToNearestHundred } from "helpers/cash_rounding"

// Drives the on_account collect form: amount-to-settle + per-event cash-only
// discount, computing the cash to collect and enabling/disabling the discount.
export default class extends Controller {
  static targets = [
    "amount", "discount", "tenderMethod",
    "settleLine", "cashToCollect", "discountLine", "balanceAfter", "discountHelper"
  ]
  static values = { balance: Number, pendingDelivery: Boolean }

  connect() { this.recalculate() }

  recalculate() {
    const amount = this.parse(this.amountTarget.value)
    const isCash = this.tenderMethodTarget.value === "cash"

    if (!isCash) {
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
    const cash = (discount > 0 && isCash) ? roundToNearestHundred(cashRaw) : cashRaw
    // The discount shown is always the exact nominal percentage — never rounded.
    // Only the cash to collect (the total/result) gets the hundred rounding.
    const discountValue = discount > 0 ? amount * discount / 100 : 0

    this.settleLineTarget.textContent = this.format(amount)
    this.discountLineTarget.textContent = `−${this.format(discountValue)}`
    this.cashToCollectTarget.textContent = this.format(cash)
    this.balanceAfterTarget.textContent = this.format(this.balanceValue - amount)
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

  parse(value) {
    return parseFloat(String(value).replace(/\./g, "").replace(",", ".")) || 0
  }

  format(n) {
    return n.toLocaleString("es-AR", { style: "currency", currency: "ARS" })
  }
}
