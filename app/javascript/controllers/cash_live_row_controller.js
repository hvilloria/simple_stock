import { Controller } from "@hotwired/stimulus"

// Keeps the cashier's hands on the keyboard: the live row takes focus as soon
// as it appears, including the fresh one a save puts back.
export default class extends Controller {
  static targets = ["firstField", "category", "channel", "subcategory"]

  connect() {
    this.toggleFields()
    this.firstFieldTarget.focus()
  }

  // A channel only means something on a sale, and a subcategory only on a fixed
  // expense. Disabling keeps them out of the submitted params, which the model
  // would otherwise reject; hiding alone would not.
  toggleFields() {
    const category = this.categoryTarget.value

    this.#show(this.channelTarget, category === "sale")
    this.#show(this.subcategoryTarget, category === "fixed_expense")
  }

  #show(field, visible) {
    field.hidden = !visible
    field.disabled = !visible
  }
}
