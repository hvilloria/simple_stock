import { Controller } from "@hotwired/stimulus"

// Controller for filter forms that auto-submit on change
// Usage: data-controller="filter-form" on the form
//      data-action="change->filter-form#submit" on selects (immediate submit)
//      data-action="input->filter-form#submitWithDebounce" on text inputs (with delay)
export default class extends Controller {
  static values = {
    delay: { type: Number, default: 300 }
  }

  disconnect() {
    // Clear the timeout if the controller disconnects
    if (this.timeout) {
      clearTimeout(this.timeout)
    }
  }

  submit() {
    // Immediate auto-submit for selects, checkboxes, etc.
    this.element.requestSubmit()
  }

  submitWithDebounce(event) {
    // Clear the previous timeout if it exists (avoids multiple requests)
    if (this.timeout) {
      clearTimeout(this.timeout)
    }

    // Create a new timeout that will submit the form after the delay
    this.timeout = setTimeout(() => {
      this.element.requestSubmit()
    }, this.delayValue)
  }
}
