import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "currencyRadio",
    "exchangeRateField",
    "exchangeRateInput",
    "invoiceSelect",
    "amountInput"
  ]

  connect() {
    this.onCurrencyChange()
  }

  // Formatear al perder foco (blur) - Formato argentino: 1.500.000,50
  formatAmount(event) {
    const input = event.target
    const rawValue = this.cleanAmountValue(input.value)
    const numValue = parseFloat(rawValue)
    
    if (!isNaN(numValue) && numValue > 0) {
      input.value = new Intl.NumberFormat('es-AR', {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2
      }).format(numValue)
    }
  }

  // Limpiar formato al hacer focus para facilitar edición
  unformatAmount(event) {
    const input = event.target
    // Remover separadores de miles (puntos), mantener coma decimal
    // 1.500.000,50 → 1500000,50
    input.value = input.value.replace(/\./g, '')
  }

  // Limpiar valor para enviar al servidor: 1.500.000,50 → 1500000.50
  cleanAmountValue(value) {
    if (!value) return ''
    // Remover puntos (separador miles) y cambiar coma por punto (decimal)
    return value.replace(/\./g, '').replace(/,/g, '.')
  }

  // CRÍTICO: Limpiar antes de enviar el formulario
  handleFormSubmit(event) {
    // Limpiar campo de monto
    if (this.hasAmountInputTarget && this.amountInputTarget.value) {
      const cleanValue = this.cleanAmountValue(this.amountInputTarget.value)
      this.amountInputTarget.value = cleanValue
    }
    
    // Limpiar campo de tipo de cambio
    if (this.hasExchangeRateInputTarget && this.exchangeRateInputTarget.value) {
      const cleanValue = this.cleanAmountValue(this.exchangeRateInputTarget.value)
      this.exchangeRateInputTarget.value = cleanValue
    }
  }

  onCurrencyChange() {
    const selectedCurrency = this.element.querySelector('input[name="credit_note[currency]"]:checked')?.value
    
    if (selectedCurrency === "USD") {
      this.exchangeRateFieldTarget.classList.remove("hidden")
      this.exchangeRateInputTarget.required = true
    } else {
      this.exchangeRateFieldTarget.classList.add("hidden")
      this.exchangeRateInputTarget.required = false
    }
  }

  async onSupplierChange(event) {
    const supplierId = event.target.value
    
    if (!supplierId) {
      this.clearInvoices()
      return
    }

    // Cargar facturas del proveedor vía AJAX
    try {
      const response = await fetch(`/web/credit_notes/supplier_invoices?supplier_id=${supplierId}`, {
        headers: {
          'Accept': 'application/json'
        }
      })
      
      if (response.ok) {
        const invoices = await response.json()
        this.updateInvoicesSelect(invoices)
      } else {
        console.error('Error loading invoices:', response.statusText)
        this.clearInvoices()
      }
    } catch (error) {
      console.error('Error loading invoices:', error)
      this.clearInvoices()
    }
  }

  onInvoiceChange(event) {
    const invoiceId = event.target.value
    
    if (!invoiceId) {
      return
    }

    // Aquí podríamos hacer un fetch para obtener currency y exchange_rate de la factura
    // y actualizarlos en el formulario automáticamente
    console.log("Invoice changed to:", invoiceId)
  }

  clearInvoices() {
    if (this.hasInvoiceSelectTarget) {
      this.invoiceSelectTarget.innerHTML = '<option value="">Sin factura asociada</option>'
    }
  }

  updateInvoicesSelect(invoices) {
    if (!this.hasInvoiceSelectTarget) {
      return
    }

    // Limpiar el select
    this.invoiceSelectTarget.innerHTML = '<option value="">Sin factura asociada</option>'

    // Agregar las facturas
    invoices.forEach(invoice => {
      const option = document.createElement('option')
      option.value = invoice.id
      option.textContent = `${invoice.number} - ARS ${this.formatCurrency(invoice.amount)}`
      this.invoiceSelectTarget.appendChild(option)
    })
  }

  formatCurrency(amount) {
    return new Intl.NumberFormat('es-AR', {
      minimumFractionDigits: 0,
      maximumFractionDigits: 0
    }).format(amount)
  }
}
