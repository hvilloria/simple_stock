import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="products-search"
export default class extends Controller {
  static values = {
    delay: { type: Number, default: 500 }
  }

  connect() {
    console.log("ProductsSearch controller connected")
  }

  disconnect() {
    // Limpiar el timeout si el controller se desconecta
    if (this.timeout) {
      clearTimeout(this.timeout)
    }
  }

  submitWithDebounce(event) {
    // Limpiar el timeout anterior si existe (evita múltiples requests)
    if (this.timeout) {
      clearTimeout(this.timeout)
    }

    // Crear nuevo timeout que enviará el form después del delay
    this.timeout = setTimeout(() => {
      this.submitForm()
    }, this.delayValue)
  }

  submitForm() {
    // Obtener el form y enviarlo
    this.element.requestSubmit()
  }
}

