# frozen_string_literal: true

require "rails_helper"

RSpec.describe InvoicesHelper, type: :helper do
  let(:invoice) { build(:invoice, :simple_mode) }

  it "counts the units the invoice's lines add" do
    invoice.invoice_items.build(product: build(:product), quantity: 10, unit_cost: 1)
    invoice.invoice_items.build(product: build(:product), quantity: 4, unit_cost: 1)

    expect(helper.invoice_units(invoice)).to eq(14)
  end

  it "names the units in the cancel confirmation of an itemized invoice" do
    invoice.invoice_items.build(product: build(:product), quantity: 15, unit_cost: 1)

    expect(helper.invoice_cancel_confirmation(invoice))
      .to eq("¿Cancelar esta factura? Se descuentan del stock las 15 unidades que sumó, hasta donde haya.")
  end

  it "names a single unit in the singular" do
    invoice.invoice_items.build(product: build(:product), quantity: 1, unit_cost: 1)

    expect(helper.invoice_units_label(invoice)).to eq("1 unidad")
  end

  describe "#invoice_cost_source_caption" do
    def caption(discount:, iva:)
      helper.invoice_cost_source_caption(build(:invoice, purchase_date: Date.new(2026, 11, 4),
                                                         discount_percentage: discount, iva_percentage: iva))
    end

    it "names what the purchase's cost includes" do
      expect(caption(discount: 10, iva: 21)).to eq("04/11/2026 · con IVA y descuento")
      expect(caption(discount: 0, iva: 21)).to eq("04/11/2026 · con IVA")
      expect(caption(discount: 10, iva: 0)).to eq("04/11/2026 · con descuento")
      expect(caption(discount: nil, iva: 0)).to eq("04/11/2026")
    end
  end

  it "keeps today's confirmation for an amount-only invoice" do
    expect(helper.invoice_cancel_confirmation(invoice)).to eq("¿Estás seguro de cancelar esta factura?")
  end
end
