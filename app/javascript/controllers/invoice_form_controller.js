import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "supplier",
    "purchaseDate",
    "dueDate",
    "exchangeRateField",
    "exchangeRateInput",
    "paymentTermInfo",
    "amount",
    "currencyInput",
    "earlyPaymentSection",
    "earlyPaymentInfo",
    "earlyPaymentDueDate",
    "earlyPaymentDiscount",
    "summaryAmount",
    "summaryDueDate",
    "summaryDiscountSection",
    "summaryEarlyDueDate",
    "summaryDiscountPct",
    "summaryDiscountedAmount"
  ]
  
  static values = { 
    submitting: { type: Boolean, default: false } 
  }

  connect() {
    console.log("Invoice form controller connected")
    
    // Calculate initial date if values already exist
    this.calculateDueDate()

    // Configure initial exchange rate visibility
    this.toggleExchangeRate()

    // Update payment term info
    this.updatePaymentTermInfo()

    // Update early payment info
    this.updateEarlyPaymentInfo()

    // Initialize summary panel
    this.updateSummaryDates()
    this.updateSummary()
  }

  // ========== AMOUNT FORMATTING ==========

  // Format on blur (losing focus)
  formatAmount(event) {
    const input = event.target
    const rawValue = this.cleanAmountValue(input.value)
    const numValue = parseFloat(rawValue)
    
    if (!isNaN(numValue) && numValue > 0) {
      // Argentine format: 1.500.000,50
      input.value = new Intl.NumberFormat('es-AR', {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2
      }).format(numValue)
    }
    this.updateSummary()
  }

  // Clear formatting on focus
  unformatAmount(event) {
    const input = event.target
    // Only remove thousands separators (dots), keep decimal comma
    // 1.500.000,50 → 1500000,50
    input.value = input.value.replace(/\./g, '')
  }

  // Clean value: 1.500.000,50 → 1500000.50
  cleanAmountValue(value) {
    if (!value) return ''
    // Remove dots (thousands separator) and change comma to dot (decimal)
    return value.replace(/\./g, '').replace(/,/g, '.')
  }

  // CRITICAL: Clean before submitting the form
  handleFormSubmit(event) {
    // Clean amount field
    if (this.hasAmountTarget && this.amountTarget.value) {
      const cleanValue = this.cleanAmountValue(this.amountTarget.value)
      this.amountTarget.value = cleanValue
      console.log('Amount enviado:', cleanValue)
    }
    
    // Clean exchange rate field
    if (this.hasExchangeRateInputTarget && this.exchangeRateInputTarget.value) {
      const cleanValue = this.cleanAmountValue(this.exchangeRateInputTarget.value)
      this.exchangeRateInputTarget.value = cleanValue
      console.log('Exchange rate enviado:', cleanValue)
    }
  }

  // ========== DATE CALCULATION ==========
  
  calculateDueDate() {
    if (!this.hasSupplierTarget) return
    const supplierSelect = this.supplierTarget
    const selectedOption = supplierSelect.options[supplierSelect.selectedIndex]
    const paymentTermDays = parseInt(selectedOption.dataset.paymentTermDays || "0")
    
    const purchaseDateValue = this.purchaseDateTarget.value
    
    if (!purchaseDateValue || paymentTermDays === 0) {
      return
    }

    // Calculate new due date
    const purchaseDate = new Date(purchaseDateValue + "T00:00:00")
    const dueDate = new Date(purchaseDate)
    dueDate.setDate(dueDate.getDate() + paymentTermDays)

    // Format to YYYY-MM-DD for the date input
    const year = dueDate.getFullYear()
    const month = String(dueDate.getMonth() + 1).padStart(2, '0')
    const day = String(dueDate.getDate()).padStart(2, '0')
    
    this.dueDateTarget.value = `${year}-${month}-${day}`
    this.updateSummaryDates()
  }

  calculateEarlyPaymentDueDate() {
    if (!this.hasEarlyPaymentDueDateTarget) return

    const supplierSelect = this.supplierTarget
    const selectedOption = supplierSelect.options[supplierSelect.selectedIndex]
    const earlyPaymentDays = parseInt(selectedOption.dataset.earlyPaymentDays || "0")
    
    const purchaseDateValue = this.purchaseDateTarget.value
    
    if (!purchaseDateValue || earlyPaymentDays === 0) {
      return
    }

    // Calculate early payment date
    const purchaseDate = new Date(purchaseDateValue + "T00:00:00")
    const earlyPaymentDate = new Date(purchaseDate)
    earlyPaymentDate.setDate(earlyPaymentDate.getDate() + earlyPaymentDays)

    // Format to YYYY-MM-DD for the date input
    const year = earlyPaymentDate.getFullYear()
    const month = String(earlyPaymentDate.getMonth() + 1).padStart(2, '0')
    const day = String(earlyPaymentDate.getDate()).padStart(2, '0')
    
    this.earlyPaymentDueDateTarget.value = `${year}-${month}-${day}`
    this.updateSummaryDates()
  }

  // ========== INFO UPDATE ==========
  
  updatePaymentTermInfo() {
    if (!this.hasPaymentTermInfoTarget) return

    const supplierSelect = this.supplierTarget
    const selectedOption = supplierSelect.options[supplierSelect.selectedIndex]
    const paymentTermDays = parseInt(selectedOption.dataset.paymentTermDays || "0")

    if (paymentTermDays > 0) {
      this.paymentTermInfoTarget.innerHTML = `
        <span class="inline-flex items-center gap-1 px-2.5 py-1 bg-blue-50 border border-blue-200 text-blue-700 text-xs rounded-lg font-medium">
          📅 Plazo: ${paymentTermDays} días
        </span>
      `
      this.paymentTermInfoTarget.style.display = 'block'
    } else {
      this.paymentTermInfoTarget.style.display = 'none'
    }
  }

  updateEarlyPaymentInfo() {
    if (!this.hasEarlyPaymentSectionTarget) return

    const supplierSelect = this.supplierTarget
    const selectedOption = supplierSelect.options[supplierSelect.selectedIndex]
    const earlyPaymentDays = parseInt(selectedOption.dataset.earlyPaymentDays || "0")
    const discountPercentage = parseFloat(selectedOption.dataset.earlyPaymentDiscount || "0")

    if (earlyPaymentDays > 0 && discountPercentage > 0) {
      // Show section
      this.earlyPaymentSectionTarget.style.display = 'block'

      // Update info text
      if (this.hasEarlyPaymentInfoTarget) {
        this.earlyPaymentInfoTarget.innerHTML = `
          <span class="inline-flex items-center gap-1 text-emerald-800">
            ⚡ ${discountPercentage}% de descuento si paga en ${earlyPaymentDays} días
          </span>
        `
      }

      // Set the discount percentage
      if (this.hasEarlyPaymentDiscountTarget) {
        this.earlyPaymentDiscountTarget.value = discountPercentage
      }

      // Show discount panel in summary
      if (this.hasSummaryDiscountSectionTarget) {
        this.summaryDiscountSectionTarget.style.display = 'block'
      }
      if (this.hasSummaryDiscountPctTarget) {
        this.summaryDiscountPctTarget.textContent = discountPercentage + '%'
      }

      // Calculate early payment date
      this.calculateEarlyPaymentDueDate()
    } else {
      // Hide section
      this.earlyPaymentSectionTarget.style.display = 'none'

      // Hide discount panel in summary
      if (this.hasSummaryDiscountSectionTarget) {
        this.summaryDiscountSectionTarget.style.display = 'none'
      }
    }

    this.updateSummary()
  }

  // ========== EVENT HANDLERS ==========
  
  // Called when the supplier changes
  onSupplierChange() {
    console.log("Supplier changed")
    this.calculateDueDate()
    this.updatePaymentTermInfo()
    this.updateEarlyPaymentInfo()
    this.calculateEarlyPaymentDueDate()
  }

  // Called when the purchase date changes
  onPurchaseDateChange() {
    console.log("Purchase date changed")
    this.calculateDueDate()
    this.calculateEarlyPaymentDueDate()
  }

  // Called when the currency changes
  toggleExchangeRate() {
    const currencyUsd = document.getElementById('currency_usd')
    const currencyArs = document.getElementById('currency_ars')
    
    if (!currencyUsd || !currencyArs || !this.hasExchangeRateFieldTarget) {
      return
    }

    if (currencyUsd.checked) {
      this.exchangeRateFieldTarget.style.display = 'block'
      // Make required when USD is selected
      if (this.hasExchangeRateInputTarget) {
        this.exchangeRateInputTarget.setAttribute('required', 'required')
      }
    } else {
      this.exchangeRateFieldTarget.style.display = 'none'
      // Remove required when ARS is selected
      if (this.hasExchangeRateInputTarget) {
        this.exchangeRateInputTarget.removeAttribute('required')
      }
    }
  }

  // ========== SUMMARY PANEL ==========

  // Updates amount and discounted amount in the right panel.
  // Called on every input of the amount field and on blur (after formatting).
  updateSummary() {
    if (!this.hasSummaryAmountTarget) return

    const raw = this.hasAmountTarget ? this.cleanAmountValue(this.amountTarget.value) : ''
    const amount = parseFloat(raw)
    const valid = !isNaN(amount) && amount > 0

    this.summaryAmountTarget.textContent = valid ? this.formatARS(amount) : '—'

    if (this.hasSummaryDiscountedAmountTarget) {
      if (valid) {
        const pct = this.hasEarlyPaymentDiscountTarget
          ? parseFloat(this.earlyPaymentDiscountTarget.value || '0')
          : 0
        const final = pct > 0 ? amount * (1 - pct / 100) : amount
        this.summaryDiscountedAmountTarget.textContent = this.formatARS(final)
      } else {
        this.summaryDiscountedAmountTarget.textContent = '—'
      }
    }
  }

  // Updates the due dates in the right panel.
  updateSummaryDates() {
    if (this.hasSummaryDueDateTarget && this.hasDueDateTarget) {
      this.summaryDueDateTarget.textContent = this.formatDateForDisplay(this.dueDateTarget.value)
    }
    if (this.hasSummaryEarlyDueDateTarget && this.hasEarlyPaymentDueDateTarget) {
      this.summaryEarlyDueDateTarget.textContent = this.formatDateForDisplay(this.earlyPaymentDueDateTarget.value)
    }
  }

  // "2026-04-15" → "15/04/2026"
  formatDateForDisplay(dateStr) {
    if (!dateStr) return '—'
    const [year, month, day] = dateStr.split('-')
    return `${day}/${month}/${year}`
  }

  // es-AR currency format: 95000.50 → "$ 95.000,50"
  formatARS(num) {
    return new Intl.NumberFormat('es-AR', {
      style: 'currency',
      currency: 'ARS',
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    }).format(num)
  }
}