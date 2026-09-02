import { Controller } from "@hotwired/stimulus"

// Keeps the cashier's hands on the keyboard: the live row takes focus as soon
// as it appears, including the fresh one a save puts back.
export default class extends Controller {
  static targets = ["firstField", "category", "channel", "subcategory", "direction"]
  // The day screen shows two live rows at once, and only one may hold the
  // caret on load; a row a save puts back always takes it.
  static values = { autofocus: { type: Boolean, default: true } }

  connect() {
    this.toggleFields()
    if (this.autofocusValue) this.firstFieldTarget.focus()
  }

  // A channel only means something on a sale, a subcategory only on a fixed
  // expense, and a direction only on a partner movement. Disabling keeps them
  // out of the submitted params, which the model would otherwise reject; hiding
  // alone would not. The arca zone has no channel at all, and only the admin
  // gets a direction, because only the admin is offered the category it needs.
  toggleFields() {
    const category = this.categoryTarget.value

    if (this.hasChannelTarget) this.#show(this.channelTarget, category === "sale")
    if (this.hasDirectionTarget) this.#show(this.directionTarget, category === "partner")
    this.#show(this.subcategoryTarget, category === "fixed_expense")
  }

  #show(field, visible) {
    field.hidden = !visible
    field.disabled = !visible
  }
}
