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
    "summaryDiscountedAmount",
    "amountCaption",
    "stockTitle",
    "stockNote",
    "stockList",
    "zeroCostModal",
    "zeroCostTitle",
    "zeroCostList",
    "zeroCostSummary"
  ]
  
  static values = { 
    submitting: { type: Boolean, default: false } 
  }

  connect() {
    this.zeroCostLines = []
    this.zeroCostConfirmed = false

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

  // Runs on the form's `submit` event: cleans the AR-formatted amounts, and
  // holds the submission once when a line is free so the operator confirms it.
  handleFormSubmit(event) {
    if (this.zeroCostLines.length > 0 && !this.zeroCostConfirmed) {
      event.preventDefault()
      this.openZeroCostModal()
      return
    }

    if (this.hasAmountTarget && this.amountTarget.value) {
      this.amountTarget.value = this.cleanAmountValue(this.amountTarget.value)
    }

    if (this.hasExchangeRateInputTarget && this.exchangeRateInputTarget.value) {
      this.exchangeRateInputTarget.value = this.cleanAmountValue(this.exchangeRateInputTarget.value)
    }
  }

  // ========== PRODUCT LINES ==========

  linesChanged(event) {
    const { lines, total, units, products, zeroCostLines } = event.detail
    this.zeroCostLines = zeroCostLines
    this.zeroCostConfirmed = false

    if (lines.length > 0) {
      if (!this.amountTarget.readOnly) this.typedAmount = this.amountTarget.value
      this.amountTarget.readOnly = true
      this.amountTarget.classList.add("bg-slate-50", "text-slate-600")
      this.amountTarget.value = new Intl.NumberFormat("es-AR", { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(total)
      this.amountCaptionTarget.textContent = "Calculado desde los productos. Quitá todas las líneas para escribirlo a mano."
      this.stockTitleTarget.textContent = `Suma stock: ${units} ${units === 1 ? "unidad" : "unidades"} en ${products} ${products === 1 ? "producto" : "productos"}`
      this.stockNoteTarget.textContent = "El stock se suma al registrar. El costo promedio no cambia."
      this.stockListTarget.innerHTML = lines.map(line =>
        `<li class="flex justify-between"><span>${line.name}</span><span>+${line.quantity}</span></li>`
      ).join("")
      this.stockListTarget.classList.remove("hidden")
    } else {
      if (this.amountTarget.readOnly) this.amountTarget.value = this.typedAmount || ""
      this.amountTarget.readOnly = false
      this.amountTarget.classList.remove("bg-slate-50", "text-slate-600")
      this.amountCaptionTarget.textContent = "Monto total de la factura (formato: 1.500.000,50)"
      this.stockTitleTarget.textContent = "Sin productos: no mueve stock"
      this.stockNoteTarget.textContent = "Se registra solo la factura, con el monto que escribas."
      this.stockListTarget.innerHTML = ""
      this.stockListTarget.classList.add("hidden")
    }

    this.updateSummary()
  }

  openZeroCostModal() {
    const count = this.zeroCostLines.length
    const checked = this.element.querySelector('input[name="currency"]:checked')
    const symbol = checked && checked.value === "USD" ? "US$" : "$"
    this.zeroCostTitleTarget.textContent = `${count} ${count === 1 ? "línea" : "líneas"} con costo 0`
    this.zeroCostListTarget.innerHTML = this.zeroCostLines.map(line =>
      `<li class="flex justify-between"><span>${line.name}</span><span>${line.quantity} ${line.quantity === 1 ? "unidad" : "unidades"} · ${symbol} 0,00</span></li>`
    ).join("")
    this.zeroCostSummaryTarget.textContent = `${this.stockTitleTarget.textContent}. Monto de la factura: ${symbol} ${this.amountTarget.value}.`
    this.zeroCostModalTarget.classList.remove("hidden")
  }

  closeZeroCostModal() {
    this.zeroCostModalTarget.classList.add("hidden")
  }

  confirmZeroCost() {
    this.zeroCostConfirmed = true
    this.closeZeroCostModal()
    this.element.requestSubmit()
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

      // Clear the inputs: hidden fields are still submitted with the form
      if (this.hasEarlyPaymentDiscountTarget) {
        this.earlyPaymentDiscountTarget.value = ''
      }
      if (this.hasEarlyPaymentDueDateTarget) {
        this.earlyPaymentDueDateTarget.value = ''
      }

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
    const checked = this.element.querySelector('input[name="currency"]:checked')
    this.element.dispatchEvent(new CustomEvent("currency-changed", { detail: { currency: checked ? checked.value : "ARS" }, bubbles: true }))

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