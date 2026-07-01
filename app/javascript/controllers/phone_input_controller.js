import { Controller } from "@hotwired/stimulus"

// Live-formats an Argentine phone input as it is typed.
// Optimized for 10-digit numbers (2-digit area code + 8-digit local):
//   1155551234 → "11 5555-1234"
// The backend normalizes to digits only when saving (Order#normalize_contact_phone),
// so the visual format does not affect the persisted value.
// Usage: data-controller="phone-input" data-action="input->phone-input#format"
export default class extends Controller {
  connect() {
    // Formats any pre-loaded value (e.g. when re-rendering after an error).
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
    // More than 10 digits: 10-digit pattern + the rest at the end.
    return `${d.slice(0, 2)} ${d.slice(2, 6)}-${d.slice(6, 10)} ${d.slice(10)}`
  }
}
