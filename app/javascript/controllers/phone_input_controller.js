import { Controller } from "@hotwired/stimulus"

// Formatea en vivo un input de teléfono argentino mientras se tipea.
// Optimizado para números de 10 dígitos (código de área de 2 + local de 8):
//   1155551234 → "11 5555-1234"
// El backend normaliza a solo dígitos al guardar (Order#normalize_contact_phone),
// así que el formato visual no afecta el valor persistido.
// Uso: data-controller="phone-input" data-action="input->phone-input#format"
export default class extends Controller {
  connect() {
    // Formatea cualquier valor pre-cargado (ej. al re-renderizar tras un error).
    this.format()
  }

  format() {
    const digits = this.element.value.replace(/\D/g, "")
    this.element.value = this.formatDigits(digits)
  }

  formatDigits(d) {
    if (d.length <= 2) return d
    if (d.length <= 6) return `${d.slice(0, 2)} ${d.slice(2)}`
    if (d.length <= 10) return `${d.slice(0, 2)} ${d.slice(2, 6)}-${d.slice(6)}`
    // Más de 10 dígitos: patrón de 10 + el resto al final.
    return `${d.slice(0, 2)} ${d.slice(2, 6)}-${d.slice(6, 10)} ${d.slice(10)}`
  }
}
