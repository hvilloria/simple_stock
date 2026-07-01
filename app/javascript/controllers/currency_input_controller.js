import { Controller } from "@hotwired/stimulus"

// Reusable controller for currency inputs in Argentine format
// Usage: data-controller="currency-input" data-action="blur->currency-input#format focus->currency-input#unformat"
export default class extends Controller {
  // Format on blur (losing focus) - Argentine format: 1.500.000,50
  format(event) {
    const input = event.target
    const rawValue = this.cleanValue(input.value)
    const numValue = parseFloat(rawValue)
    
    if (!isNaN(numValue) && numValue >= 0) {
      input.value = new Intl.NumberFormat('es-AR', {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2
      }).format(numValue)
    } else if (input.value === '') {
      // If empty, do nothing (allow optional fields)
    } else {
      // If invalid, clear
      input.value = ''
    }
  }

  // Clear formatting on focus - remove thousands separators, keep comma
  // 1.500.000,50 → 1500000,50
  unformat(event) {
    const input = event.target
    input.value = input.value.replace(/\./g, '')
  }

  // Clean value to send to the backend: 1.500.000,50 → 1500000.50
  cleanValue(value) {
    if (!value) return ''
    // Remove dots (thousands separator) and change comma to dot (decimal)
    return value.replace(/\./g, '').replace(/,/g, '.')
  }

  // Method to be called before form submit
  prepareForSubmit(input) {
    const cleanValue = this.cleanValue(input.value)
    input.value = cleanValue
  }
}
