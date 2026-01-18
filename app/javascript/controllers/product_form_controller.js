import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  handleSubmit(event) {
    // Buscar todos los inputs con currency-input controller y limpiar sus valores
    const currencyInputs = this.element.querySelectorAll('[data-controller~="currency-input"]')
    
    currencyInputs.forEach(input => {
      if (input.value) {
        // Limpiar formato argentino: 1.500.000,50 → 1500000.50
        const cleaned = input.value.replace(/\./g, '').replace(/,/g, '.')
        input.value = cleaned
      }
    })
  }
}
