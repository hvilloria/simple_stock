import { Controller } from "@hotwired/stimulus"

const MODES = ["in", "out", "move"]
const MODE_KEYS = { e: "in", s: "out", t: "move" }
const DEFAULT_PILE = "drawer"

// The day's entry row. The operator answers which way the money went, what it
// was and how it was paid; this writes those answers into the parameters the
// server takes — category, subcategory, direction and account — and keeps the
// focus on the mode control so a day can be loaded without the mouse.
export default class extends Controller {
  static targets = [
    "mode", "group", "kind", "channel", "supplier", "method", "pile",
    "category", "subcategory", "direction", "account", "original"
  ]
  static values = { mode: String, edit: Boolean }

  connect() {
    this.refresh()
    this.#focus()
  }

  select(event) {
    this.#switchTo(event.currentTarget.dataset.mode)
  }

  // Bound to the mode buttons only, so a letter typed into a text field never
  // reaches it.
  key(event) {
    if (event.altKey || event.ctrlKey || event.metaKey) return

    const mode = MODE_KEYS[event.key.toLowerCase()] ?? this.#step(event.key)
    if (!mode) return

    event.preventDefault()
    this.#switchTo(mode)
  }

  cancel(event) {
    event.preventDefault()
    this.element.replaceWith(this.originalTarget.content.cloneNode(true))
  }

  // kind, method and pile exist once per group, so each rule reads the active
  // group's own. A group without a kind select is a sale: only the partner
  // category adds the choice.
  refresh() {
    const mode = this.modeValue
    this.modeTargets.forEach((button) => {
      const pressed = button.dataset.mode === mode
      button.setAttribute("aria-pressed", String(pressed))
      button.tabIndex = pressed ? 0 : -1
    })
    this.groupTargets.forEach((group) => this.#show(group, group.dataset.mode === mode))
    if (mode === "move") return

    const group = this.#group(mode)
    const [category, subcategory = ""] = (this.#within(group, this.kindTargets)?.value ?? "sale").split(":")
    const channel = this.#within(group, this.channelTargets)
    const supplier = this.#within(group, this.supplierTargets)
    const method = this.#within(group, this.methodTargets)
    const pile = this.#within(group, this.pileTargets)
    const sale = category === "sale"
    const cash = method.value === "cash"

    if (channel) this.#show(channel, sale)
    if (supplier) this.#show(supplier, sale && channel.value === "compensation")
    this.#show(method, !sale)
    this.#show(pile, !sale && cash)
    if (!cash) pile.value = DEFAULT_PILE

    this.categoryTarget.value = category
    this.subcategoryTarget.value = subcategory
    this.directionTarget.value = category === "partner" ? (mode === "in" ? "contribution" : "withdrawal") : ""
    this.accountTarget.disabled = sale
    this.accountTarget.value = sale ? "" : (cash ? pile.value : method.value)
  }

  #switchTo(mode) {
    if (this.editValue || !MODES.includes(mode)) return

    this.modeValue = mode
    this.refresh()
    this.#modeButton.focus()
  }

  #step(key) {
    const offset = { ArrowLeft: -1, ArrowRight: 1 }[key]
    if (!offset) return null

    const index = MODES.indexOf(this.modeValue) + offset
    return MODES[(index + MODES.length) % MODES.length]
  }

  // Editing locks the mode, so an edit form hands the caret to its first field.
  #focus() {
    if (this.editValue) {
      this.#group(this.modeValue).querySelector("input[type=text]")?.focus()
    } else {
      this.#modeButton.focus()
    }
  }

  get #modeButton() {
    return this.modeTargets.find((button) => button.dataset.mode === this.modeValue)
  }

  #group(mode) {
    return this.groupTargets.find((group) => group.dataset.mode === mode)
  }

  #within(group, targets) {
    return targets.find((target) => group.contains(target))
  }

  // A field that does not apply is disabled as well as hidden: hiding alone
  // would still submit it. A conditional field is hidden through its label.
  #show(field, visible) {
    (field.closest("label") ?? field).hidden = !visible
    field.disabled = !visible
  }
}
