import { Controller } from "@hotwired/stimulus"

// Manages the multi-order payment form:
// - Checkbox toggles row inputs and prefills amount with pending
// - Any change recalculates totals (charging now / remaining balance / selected count)
export default class extends Controller {
  static targets = ["row", "totalCharging", "remainingBalance", "selectedCount", "submitButton"]
  static values = { totalDebt: Number }

  connect() {
    this.updateSummary()
  }

  toggleRow(event) {
    const row = event.target.closest("[data-payment-allocation-target='row']")
    const amountInput = row.querySelector("[data-role='amount-input']")
    const methodSelect = row.querySelector("[data-role='method-select']")
    const pending = parseFloat(row.dataset.pending)

    if (event.target.checked) {
      amountInput.disabled = false
      methodSelect.disabled = false
      amountInput.value = pending.toFixed(2)
      row.classList.remove("opacity-60")
    } else {
      amountInput.disabled = true
      methodSelect.disabled = true
      amountInput.value = ""
      row.classList.add("opacity-60")
    }

    this.updateSummary()
  }

  recalc() {
    this.updateSummary()
  }

  updateSummary() {
    let charging = 0
    let selected = 0

    this.rowTargets.forEach(row => {
      const checkbox = row.querySelector("[data-role='include-checkbox']")
      const amountInput = row.querySelector("[data-role='amount-input']")
      if (checkbox.checked && amountInput.value) {
        const v = parseFloat(amountInput.value) || 0
        charging += v
        if (v > 0) selected += 1
      }
    })

    const remaining = this.totalDebtValue - charging

    this.totalChargingTarget.textContent = this.formatMoney(charging)
    this.remainingBalanceTarget.textContent = this.formatMoney(remaining)
    this.selectedCountTarget.textContent = selected

    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.disabled = selected === 0
    }
  }

  formatMoney(value) {
    return "$" + Math.round(value).toLocaleString("es-AR")
  }
}
