import { Controller } from "@hotwired/stimulus"

// A movement between arcas writes two rows, so the form shows them before it
// saves. Touching any field drops the preview on screen: confirming a stale one
// would write a pair the cashier never actually saw.
export default class extends Controller {
  static targets = ["panel", "firstField", "preview"]

  toggle() {
    this.panelTarget.hidden = !this.panelTarget.hidden
    if (!this.panelTarget.hidden) this.firstFieldTarget.focus()
  }

  invalidate() {
    this.previewTarget.innerHTML = ""
  }
}
