import { Controller } from "@hotwired/stimulus"

// Controller reutilizable para inputs de moneda en formato argentino
// Uso: data-controller="currency-input" data-action="blur->currency-input#format focus->currency-input#unformat"
export default class extends Controller {
  // Formatear al perder foco (blur) - formato argentino: 1.500.000,50
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
      // Si está vacío, no hacer nada (permitir campos opcionales)
    } else {
      // Si es inválido, limpiar
      input.value = ''
    }
  }

  // Limpiar formato al hacer focus - remover separadores de miles, mantener coma
  // 1.500.000,50 → 1500000,50
  unformat(event) {
    const input = event.target
    input.value = input.value.replace(/\./g, '')
  }

  // Limpiar valor para enviar al backend: 1.500.000,50 → 1500000.50
  cleanValue(value) {
    if (!value) return ''
    // Remover puntos (separador miles) y cambiar coma por punto (decimal)
    return value.replace(/\./g, '').replace(/,/g, '.')
  }

  // Método para ser llamado antes de submit del formulario
  prepareForSubmit(input) {
    const cleanValue = this.cleanValue(input.value)
    input.value = cleanValue
  }
}
