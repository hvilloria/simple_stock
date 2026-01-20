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
    "earlyPaymentDiscount"
  ]
  
  static values = { 
    submitting: { type: Boolean, default: false } 
  }

  connect() {
    console.log("Invoice form controller connected")
    
    // Calcular fecha inicial si ya hay valores
    this.calculateDueDate()
    
    // Configurar visibilidad inicial del tipo de cambio
    this.toggleExchangeRate()
    
    // Actualizar info de plazo
    this.updatePaymentTermInfo()
    
    // Actualizar info de early payment
    this.updateEarlyPaymentInfo()
  }

  // ========== FORMATEO DE MONTOS ==========
  
  // Formatear al perder foco (blur)
  formatAmount(event) {
    const input = event.target
    const rawValue = this.cleanAmountValue(input.value)
    const numValue = parseFloat(rawValue)
    
    if (!isNaN(numValue) && numValue > 0) {
      // Formato argentino: 1.500.000,50
      input.value = new Intl.NumberFormat('es-AR', {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2
      }).format(numValue)
    }
  }

  // Limpiar formato al hacer focus
  unformatAmount(event) {
    const input = event.target
    // Solo remover separadores de miles (puntos), mantener coma decimal
    // 1.500.000,50 → 1500000,50
    input.value = input.value.replace(/\./g, '')
  }

  // Limpiar valor: 1.500.000,50 → 1500000.50
  cleanAmountValue(value) {
    if (!value) return ''
    // Remover puntos (separador miles) y cambiar coma por punto (decimal)
    return value.replace(/\./g, '').replace(/,/g, '.')
  }

  // CRÍTICO: Limpiar antes de enviar el formulario
  handleFormSubmit(event) {
    // Limpiar campo de monto
    if (this.hasAmountTarget && this.amountTarget.value) {
      const cleanValue = this.cleanAmountValue(this.amountTarget.value)
      this.amountTarget.value = cleanValue
      console.log('Amount enviado:', cleanValue)
    }
    
    // Limpiar campo de tipo de cambio
    if (this.hasExchangeRateInputTarget && this.exchangeRateInputTarget.value) {
      const cleanValue = this.cleanAmountValue(this.exchangeRateInputTarget.value)
      this.exchangeRateInputTarget.value = cleanValue
      console.log('Exchange rate enviado:', cleanValue)
    }
  }

  // ========== CÁLCULO DE FECHAS ==========
  
  calculateDueDate() {
    const supplierSelect = this.supplierTarget
    const selectedOption = supplierSelect.options[supplierSelect.selectedIndex]
    const paymentTermDays = parseInt(selectedOption.dataset.paymentTermDays || "0")
    
    const purchaseDateValue = this.purchaseDateTarget.value
    
    if (!purchaseDateValue || paymentTermDays === 0) {
      return
    }

    // Calcular nueva fecha de vencimiento
    const purchaseDate = new Date(purchaseDateValue + "T00:00:00")
    const dueDate = new Date(purchaseDate)
    dueDate.setDate(dueDate.getDate() + paymentTermDays)

    // Formatear a YYYY-MM-DD para el input date
    const year = dueDate.getFullYear()
    const month = String(dueDate.getMonth() + 1).padStart(2, '0')
    const day = String(dueDate.getDate()).padStart(2, '0')
    
    this.dueDateTarget.value = `${year}-${month}-${day}`
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

    // Calcular fecha de early payment
    const purchaseDate = new Date(purchaseDateValue + "T00:00:00")
    const earlyPaymentDate = new Date(purchaseDate)
    earlyPaymentDate.setDate(earlyPaymentDate.getDate() + earlyPaymentDays)

    // Formatear a YYYY-MM-DD para el input date
    const year = earlyPaymentDate.getFullYear()
    const month = String(earlyPaymentDate.getMonth() + 1).padStart(2, '0')
    const day = String(earlyPaymentDate.getDate()).padStart(2, '0')
    
    this.earlyPaymentDueDateTarget.value = `${year}-${month}-${day}`
  }

  // ========== ACTUALIZACIÓN DE INFO ==========
  
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
      // Mostrar sección
      this.earlyPaymentSectionTarget.style.display = 'block'
      
      // Actualizar info text
      if (this.hasEarlyPaymentInfoTarget) {
        this.earlyPaymentInfoTarget.innerHTML = `
          <span class="inline-flex items-center gap-1 text-emerald-800">
            ⚡ ${discountPercentage}% de descuento si paga en ${earlyPaymentDays} días
          </span>
        `
      }

      // Setear el porcentaje de descuento
      if (this.hasEarlyPaymentDiscountTarget) {
        this.earlyPaymentDiscountTarget.value = discountPercentage
      }

      // Calcular fecha de early payment
      this.calculateEarlyPaymentDueDate()
    } else {
      // Ocultar sección
      this.earlyPaymentSectionTarget.style.display = 'none'
    }
  }

  // ========== EVENT HANDLERS ==========
  
  // Se llama cuando cambia el proveedor
  onSupplierChange() {
    console.log("Supplier changed")
    this.calculateDueDate()
    this.updatePaymentTermInfo()
    this.updateEarlyPaymentInfo()
    this.calculateEarlyPaymentDueDate()
  }

  // Se llama cuando cambia la fecha de compra
  onPurchaseDateChange() {
    console.log("Purchase date changed")
    this.calculateDueDate()
    this.calculateEarlyPaymentDueDate()
  }

  // Se llama cuando cambia la moneda
  toggleExchangeRate() {
    const currencyUsd = document.getElementById('currency_usd')
    const currencyArs = document.getElementById('currency_ars')
    
    if (!currencyUsd || !currencyArs || !this.hasExchangeRateFieldTarget) {
      return
    }

    if (currencyUsd.checked) {
      this.exchangeRateFieldTarget.style.display = 'block'
      // Hacer required cuando USD está seleccionado
      if (this.hasExchangeRateInputTarget) {
        this.exchangeRateInputTarget.setAttribute('required', 'required')
      }
    } else {
      this.exchangeRateFieldTarget.style.display = 'none'
      // Remover required cuando ARS está seleccionado
      if (this.hasExchangeRateInputTarget) {
        this.exchangeRateInputTarget.removeAttribute('required')
      }
    }
  }
}