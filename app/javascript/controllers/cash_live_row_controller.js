import { Controller } from "@hotwired/stimulus"

// Keeps the cashier's hands on the keyboard: the live row takes focus as soon
// as it appears, including the fresh one a save puts back.
export default class extends Controller {
  static targets = ["firstField", "category", "channel", "subcategory", "direction", "supplier"]
  // The day screen shows two live rows at once, and only one may hold the
  // caret on load; a row a save puts back always takes it.
  static values = { autofocus: { type: Boolean, default: true } }

  connect() {
    this.toggleFields()
    if (this.autofocusValue) this.firstFieldTarget.focus()
  }

  // One rule per conditional field: the field shows where it means something
  // and is disabled everywhere else. Disabling keeps it out of the submitted
  // params, which the model would otherwise reject; hiding alone would not.
  // The guards are not conditions but presence checks: the arca zone has no
  // channel and no supplier, and only the admin is offered a direction.
  toggleFields() {
    const category = this.categoryTarget.value
    const channel = this.hasChannelTarget ? this.channelTarget.value : null

    if (this.hasChannelTarget) this.#show(this.channelTarget, category === "sale")
    if (this.hasSubcategoryTarget) this.#show(this.subcategoryTarget, category === "fixed_expense")
    if (this.hasDirectionTarget) this.#show(this.directionTarget, category === "partner")
    if (this.hasSupplierTarget) this.#show(this.supplierTarget, category === "sale" && channel === "compensation")
  }

  #show(field, visible) {
    field.hidden = !visible
    field.disabled = !visible
  }
}
