import { Controller } from "@hotwired/stimulus"

// Manages the multi-order payment form with per-product discounts.
// - Each card represents one credit order.
// - Ticking a card enables inputs, expands the products block, and prefills "Cobrar" with the post-discount total.
// - Discount selects only run when the order is unlocked (no prior allocations).
// - Locked cards render their percentages as plain "(fijado)" text in HAML; this controller never enables their selects.
export default class extends Controller {
  static targets = ["row", "totalCharging", "remainingBalance", "selectedCount", "submitButton"]
  static values = { totalDebt: Number }

  connect() {
    this.updateSummary()
  }

  toggleRow(event) {
    const row = event.target.closest("[data-payment-allocation-target='row']")
    this.enableRow(row, event.target.checked)
    this.updateSummary()
  }

  toggleProducts(event) {
    const row = event.target.closest("[data-payment-allocation-target='row']")
    const block = row.querySelector("[data-role='products-block']")
    block.classList.toggle("hidden")
    const button = event.currentTarget
    button.textContent = button.textContent.includes("▸")
      ? button.textContent.replace("▸", "▾")
      : button.textContent.replace("▾", "▸")
  }

  discountChanged(event) {
    const row = event.target.closest("[data-payment-allocation-target='row']")
    this.recomputeCard(row)
    this.updateSummary()
  }

  recalc() {
    this.updateSummary()
  }

  enableRow(row, enabled) {
    const amountInput = row.querySelector("[data-role='amount-input']")
    const methodSelect = row.querySelector("[data-role='method-select']")
    const productsBlock = row.querySelector("[data-role='products-block']")
    const locked = row.dataset.locked === "true"

    if (enabled) {
      amountInput.disabled = false
      methodSelect.disabled = false
      productsBlock.classList.remove("hidden")
      if (!locked) {
        row.querySelectorAll("[data-role='discount-select']").forEach(sel => { sel.disabled = false })
      }
      this.recomputeCard(row)
    } else {
      amountInput.disabled = true
      methodSelect.disabled = true
      amountInput.value = ""
      productsBlock.classList.add("hidden")
      row.querySelectorAll("[data-role='discount-select']").forEach(sel => { sel.disabled = true })
    }
  }

  recomputeCard(row) {
    const locked = row.dataset.locked === "true"
    if (locked) return  // Locked cards keep server-rendered totals; nothing to recompute.

    let originalSum = 0
    let newSum = 0

    row.querySelectorAll("tbody tr").forEach(tr => {
      const sel = tr.querySelector("[data-role='discount-select']")
      if (!sel) return
      const unit = parseFloat(sel.dataset.unitPrice) || 0
      const qty = parseFloat(sel.dataset.quantity) || 0
      const pct = parseFloat(sel.value) || 0
      const lineOriginal = unit * qty
      const lineNew = lineOriginal * (1 - pct / 100)
      originalSum += lineOriginal
      newSum += lineNew
      const subtotalCell = tr.querySelector("[data-role='subtotal-cell']")
      if (subtotalCell) {
        subtotalCell.textContent = this.formatMoney(lineNew)
      }
    })

    const summary = row.querySelector("[data-role='discount-summary']")
    if (summary) {
      if (originalSum > 0 && Math.abs(originalSum - newSum) > 0.001) {
        summary.classList.remove("hidden")
        const orig = summary.querySelector("[data-role='summary-original']")
        const ne = summary.querySelector("[data-role='summary-new']")
        if (orig) orig.textContent = this.formatMoney(originalSum)
        if (ne) ne.textContent = this.formatMoney(newSum)
      } else {
        summary.classList.add("hidden")
      }
    }

    // Unlocked orders have paid_so_far == 0, so the new pending equals the new total.
    row.dataset.pending = newSum.toFixed(2)
    // Discount forgiven on this order (debt the customer no longer owes once charged).
    row.dataset.discountForgiven = (originalSum - newSum).toFixed(2)
    const amountInput = row.querySelector("[data-role='amount-input']")
    const checkbox = row.querySelector("[data-role='include-checkbox']")
    if (checkbox.checked) {
      amountInput.value = this.formatAmount(newSum)
    }
  }

  updateSummary() {
    let charging = 0
    let totalDiscount = 0
    let selected = 0

    this.rowTargets.forEach(row => {
      const checkbox = row.querySelector("[data-role='include-checkbox']")
      const amountInput = row.querySelector("[data-role='amount-input']")
      if (checkbox.checked && amountInput.value) {
        const v = this.parseAmount(amountInput.value)
        charging += v
        totalDiscount += parseFloat(row.dataset.discountForgiven) || 0
        if (v > 0) selected += 1
      }
    })

    const remaining = this.totalDebtValue - charging - totalDiscount

    this.totalChargingTarget.textContent = this.formatMoney(charging)
    this.remainingBalanceTarget.textContent = this.formatMoney(remaining)
    this.selectedCountTarget.textContent = selected

    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.disabled = selected === 0
    }
  }

  parseAmount(value) {
    if (!value) return 0
    return parseFloat(value.replace(/\./g, "").replace(/,/g, ".")) || 0
  }

  formatAmount(value) {
    return new Intl.NumberFormat("es-AR", {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    }).format(value || 0)
  }

  formatMoney(value) {
    return "$" + Math.round(value).toLocaleString("es-AR")
  }
}
