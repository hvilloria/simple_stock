import { Controller } from "@hotwired/stimulus"

// Opens the invoice form in place; the number only applies to A and B.
export default class extends Controller {
  static targets = ["summary", "form", "number"]
  static values = { open: Boolean }

  connect() {
    if (this.openValue) this.show()
    this.typeChanged()
  }

  show() {
    this.summaryTarget.classList.add("hidden")
    this.formTarget.classList.remove("hidden")
  }

  hide() {
    this.formTarget.classList.add("hidden")
    this.summaryTarget.classList.remove("hidden")
  }

  typeChanged() {
    const selected = this.formTarget.querySelector("input[name='invoice_type']:checked")
    const needsNumber = selected !== null && ["a", "b"].includes(selected.value)
    this.numberTarget.classList.toggle("hidden", !needsNumber)
  }
}
