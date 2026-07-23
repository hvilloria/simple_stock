import { Controller } from "@hotwired/stimulus"

// Glue for the on_account item edit form: catches product-search selections,
// keeps the hidden product_id in sync and previews subtotal/total/balance.
export default class extends Controller {
  static targets = ["productId", "quantity", "selectedName", "selectedPrice",
                    "selectedBadge", "subtotal", "total", "balance", "submit"]
  static values = {
    originalProductId: Number,
    originalQuantity: Number,
    unitPrice: Number,   // current line price
    orderTotal: Number,
    orderPaid: Number
  }

  connect() {
    this.selectedCatalogPrice = this.unitPriceValue
    this.recompute()
  }

  productSelected(event) {
    const product = event.detail.product
    this.productIdTarget.value = product.id
    this.selectedNameTarget.textContent = `${product.name} · SKU ${product.sku}`
    this.selectedCatalogPrice = Number(product.price_unit) || 0
    this.selectedBadgeTarget.classList.toggle("hidden", product.id !== this.originalProductIdValue)
    this.recompute()
  }

  recompute() {
    const productId = parseInt(this.productIdTarget.value, 10)
    const quantity = parseInt(this.quantityTarget.value, 10) || 0
    const price = productId === this.originalProductIdValue
      ? this.unitPriceValue
      : this.selectedCatalogPrice

    const oldSubtotal = this.originalQuantityValue * this.unitPriceValue
    const newSubtotal = quantity * price
    const newTotal = this.orderTotalValue + (newSubtotal - oldSubtotal)
    const newBalance = newTotal - this.orderPaidValue

    this.selectedPriceTarget.textContent = `Precio catálogo: $ ${this.format(price)}`
    this.subtotalTarget.textContent = `$ ${this.format(oldSubtotal)} → $ ${this.format(newSubtotal)}`
    this.totalTarget.textContent = `$ ${this.format(this.orderTotalValue)} → $ ${this.format(newTotal)}`
    this.balanceTarget.textContent =
      `$ ${this.format(this.orderTotalValue - this.orderPaidValue)} → $ ${this.format(newBalance)}`

    const productChanged = productId !== this.originalProductIdValue
    const changed = productChanged || quantity !== this.originalQuantityValue

    // Catalog price is only consulted (and must be positive) when the product
    // changes; a quantity-only edit keeps the line's own price, mirroring the backend.
    this.submitTarget.disabled = !(changed && quantity >= 1 && (!productChanged || price > 0))
  }

  format(n) {
    return Number(n).toLocaleString("es-AR", { minimumFractionDigits: 2, maximumFractionDigits: 2 })
  }
}
