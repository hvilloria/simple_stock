import { Controller } from "@hotwired/stimulus"

// The pay modal: confirm stays off until an origin is picked, and the amount
// follows the date because the early-payment discount ends on a deadline.
export default class extends Controller {
  static targets = ["date", "amount", "submit", "origin"]
  static values = { full: Number, discounted: Number, deadline: String }

  connect() { this.refresh() }

  refresh() {
    const origin = this.element.querySelector("input[name='account']:checked")
    this.submitTarget.disabled = !origin
    const label = origin ? origin.closest("label").textContent.trim() : null
    this.originTarget.textContent = label ? `Sale de ${label}` : "Elegí de dónde sale la plata"
    this.amountTarget.textContent = this.format(this.due())
  }

  due() {
    if (!this.deadlineValue) return this.fullValue
    return this.dateTarget.value && this.dateTarget.value <= this.deadlineValue ? this.discountedValue : this.fullValue
  }

  format(amount) {
    return "$ " + new Intl.NumberFormat("es-AR", { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(amount)
  }
}
