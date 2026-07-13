import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal", "purchaseId", "form"]

  open(event) {
    event.preventDefault()
    const purchaseId = event.currentTarget.dataset.purchaseId
    const invoiceNumber = event.currentTarget.dataset.invoiceNumber
    
    // Update the form action with the correct purchase_id
    const form = this.modalTarget.querySelector('form')
    form.action = `/web/invoices/${invoiceId}/mark_as_paid`
    
    // Update the title with the invoice number
    const title = this.modalTarget.querySelector('[data-modal-title]')
    if (title) {
      title.textContent = `Marcar Factura ${invoiceNumber} como Pagada`
    }
    
    // Show the modal
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
