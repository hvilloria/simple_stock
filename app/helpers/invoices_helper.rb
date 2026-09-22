# frozen_string_literal: true

module InvoicesHelper
  def invoice_units(invoice)
    invoice.invoice_items.sum(&:quantity)
  end

  # The Rails inflector pluralizes "unidad" as "unidads", so the Spanish plural
  # is named here.
  def invoice_units_label(invoice)
    units = invoice_units(invoice)
    "#{units} #{units == 1 ? 'unidad' : 'unidades'}"
  end

  def invoice_cancel_confirmation(invoice)
    return "¿Estás seguro de cancelar esta factura?" if invoice_units(invoice).zero?

    "¿Cancelar esta factura? Se descuentan del stock las #{invoice_units_label(invoice)} que sumó, hasta donde haya."
  end
end
