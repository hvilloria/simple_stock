import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["creditAccountCheckbox"]

  connect() {
    this.applyCreditAccountState()
  }

  customerTypeChanged(event) {
    this.applyCreditAccountStateForValue(event.target.value)
  }

  applyCreditAccountState() {
    const select = this.element.querySelector('select[name="customer[customer_type]"]')
    if (!select) return

    this.applyCreditAccountStateForValue(select.value)
  }

  applyCreditAccountStateForValue(value) {
    if (!this.hasCreditAccountCheckboxTarget) return

    if (value === "retail") {
      this.creditAccountCheckboxTarget.checked = false
      this.creditAccountCheckboxTarget.disabled = true
    } else {
      this.creditAccountCheckboxTarget.disabled = false
    }
  }
}
