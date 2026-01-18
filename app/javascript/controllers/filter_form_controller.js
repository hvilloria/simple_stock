import { Controller } from "@hotwired/stimulus"

// Controller para formularios de filtros que se auto-submiten al cambiar
// Uso: data-controller="filter-form" en el form
//      data-action="change->filter-form#submit" en selects (submit inmediato)
//      data-action="input->filter-form#submitWithDebounce" en text inputs (con delay)
export default class extends Controller {
  static values = {
    delay: { type: Number, default: 300 }
  }

  disconnect() {
    // Limpiar el timeout si el controller se desconecta
    if (this.timeout) {
      clearTimeout(this.timeout)
    }
  }

  submit() {
    // Auto-submit inmediato para selects, checkboxes, etc.
    this.element.requestSubmit()
  }

  submitWithDebounce(event) {
    // Limpiar el timeout anterior si existe (evita múltiples requests)
    if (this.timeout) {
      clearTimeout(this.timeout)
    }

    // Crear nuevo timeout que enviará el form después del delay
    this.timeout = setTimeout(() => {
      this.element.requestSubmit()
    }, this.delayValue)
  }
}
