import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  handleSubmit(event) {
    // Find all inputs with the currency-input controller and clean their values
    const currencyInputs = this.element.querySelectorAll('[data-controller~="currency-input"]')
    
    currencyInputs.forEach(input => {
      if (input.value) {
        // Clean Argentine format: 1.500.000,50 → 1500000.50
        const cleaned = input.value.replace(/\./g, '').replace(/,/g, '.')
        input.value = cleaned
      }
    })
  }
}
