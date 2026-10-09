import { Controller } from "@hotwired/stimulus"

// Enter inside a form field leaves the field instead of submitting the form,
// so currency inputs format on blur. The form submits only from its button.
export default class extends Controller {
  blur(event) {
    if (event.key !== "Enter") return
    if (!event.target.matches("input:not([type=submit]):not([type=button])")) return

    event.preventDefault()
    event.target.blur()
  }
}
