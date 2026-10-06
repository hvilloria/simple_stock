import { Controller } from "@hotwired/stimulus"

const OFFERING_TYPES = ["supplier", "utilities"]

export default class extends Controller {
  static targets = ["typeBox", "card", "link", "actions"]

  connect() {
    this.opened = new Set(
      this.cardTargets.filter((card) => this.hasValues(card)).map((card) => card.dataset.section)
    )
    this.refresh()
  }

  open({ params: { section } }) {
    this.opened.add(section)
    this.refresh()
  }

  remove({ params: { section } }) {
    const card = this.cardTargets.find((target) => target.dataset.section === section)
    card.querySelectorAll("input").forEach((input) => { input.value = "" })
    this.opened.delete(section)
    this.refresh()
  }

  refresh() {
    const offered = this.offered()

    this.cardTargets.forEach((card) => {
      const section = card.dataset.section
      if (!offered && !this.hasValues(card)) this.opened.delete(section)
      card.disabled = !offered
      card.hidden = !(offered && this.opened.has(section))
    })

    this.linkTargets.forEach((link) => {
      link.hidden = !offered || this.opened.has(link.dataset.section)
    })

    this.actionsTarget.hidden = this.linkTargets.every((link) => link.hidden)
  }

  offered() {
    return this.typeBoxTargets.some((box) => box.checked && OFFERING_TYPES.includes(box.value))
  }

  hasValues(card) {
    return Array.from(card.querySelectorAll("input")).some((input) => input.value.trim() !== "")
  }
}
