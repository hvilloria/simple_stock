import { Controller } from "@hotwired/stimulus"

// The closing modal reacts to what the cashier types. The note only exists as
// the description of a discrepancy movement, so it is offered only once the
// count differs from the expectation — always visible, it would invite an
// explanation the close silently discards.
export default class extends Controller {
  static targets = [
    "counted", "note", "wrapAmount",
    "paywayInput", "paywayDiff",
    "mercadoPagoInput", "mercadoPagoDiff"
  ]

  static values = {
    expected: Number,
    paywayRecorded: Number,
    mercadoPagoRecorded: Number
  }

  connect() {
    this.countedChanged()
    this.digitalChanged()
  }

  countedChanged() {
    const raw = this.countedTarget.value.trim()
    const counted = this.parseAmount(raw)

    this.noteTarget.hidden = raw === "" || counted === this.expectedValue
    // Once counted, the amount to wrap is what was counted, not what was expected.
    this.wrapAmountTarget.textContent =
      this.formatAmount(raw === "" ? Math.max(this.expectedValue, 0) : counted)
  }

  digitalChanged() {
    this.renderDifference(this.paywayInputTarget, this.paywayDiffTarget, this.paywayRecordedValue)
    this.renderDifference(this.mercadoPagoInputTarget, this.mercadoPagoDiffTarget, this.mercadoPagoRecordedValue)
  }

  renderDifference(input, output, recorded) {
    const raw = input.value.trim()

    if (raw === "") {
      output.hidden = true
      return
    }

    const difference = this.parseAmount(raw) - recorded
    output.hidden = false
    output.textContent =
      difference === 0 ? "Coincide" : `Diferencia: ${this.formatAmount(difference)}`
  }

  // AR currency format to number: "200.000,67" -> 200000.67
  parseAmount(value) {
    if (!value) return 0
    return parseFloat(value.replace(/\./g, "").replace(/,/g, ".")) || 0
  }

  // Number to AR currency format, matching currency-input#format.
  formatAmount(value) {
    return new Intl.NumberFormat("es-AR", {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    }).format(value || 0)
  }
}
