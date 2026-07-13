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
    // Clear the timeout if the controller disconnects
    if (this.timeout) {
      clearTimeout(this.timeout)
    }
  }

  submitWithDebounce(event) {
    // Clear the previous timeout if it exists (avoids multiple requests)
    if (this.timeout) {
      clearTimeout(this.timeout)
    }

    // Create a new timeout that will submit the form after the delay
    this.timeout = setTimeout(() => {
      this.submitForm()
    }, this.delayValue)
  }

  submitForm() {
    // Get the form and submit it
    this.element.requestSubmit()
  }
}

