import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal", "purchaseId", "form"]

  open(event) {
    event.preventDefault()
    const purchaseId = event.currentTarget.dataset.purchaseId
    const invoiceNumber = event.currentTarget.dataset.invoiceNumber
    
    // Actualizar el form action con el purchase_id correcto
    const form = this.modalTarget.querySelector('form')
    form.action = `/web/purchases/${purchaseId}/mark_as_paid`
    
    // Actualizar el título con el número de factura
    const title = this.modalTarget.querySelector('[data-modal-title]')
    if (title) {
      title.textContent = `Marcar Factura ${invoiceNumber} como Pagada`
    }
    
    // Mostrar el modal
    this.modalTarget.classList.remove('hidden')
  }

  close(event) {
    if (event) event.preventDefault()
    this.modalTarget.classList.add('hidden')
  }

  preventClose(event) {
    event.stopPropagation()
  }

  closeOnBackground(event) {
    if (event.target === event.currentTarget) {
      this.close()
    }
  }
}
