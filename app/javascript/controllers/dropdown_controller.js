import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu", "arrow"]

  connect() {
    // Auto-open only if there is an active item in the submenu
    const activeItem = this.menuTarget.querySelector('.nav-subitem.active')
    if (activeItem) {
      this.open()
    }
  }

  toggle(event) {
    event.preventDefault()

    if (this.isOpen()) {
      this.close()
    } else {
      this.open()
    }
  }

  isOpen() {
    return this.menuTarget.classList.contains('open')
  }

  open() {
    this.menuTarget.classList.add('open')
    this.arrowTarget.classList.add('rotated')
  }

  close() {
    this.menuTarget.classList.remove('open')
    this.arrowTarget.classList.remove('rotated')
  }
}
