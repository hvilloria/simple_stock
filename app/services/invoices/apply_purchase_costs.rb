# frozen_string_literal: true

module Invoices
  # A registered purchase sets each product's cost to the line's final unit
  # cost in pesos and makes the line its cost source, keeping the cost and
  # source it replaced on the line so a cancel can put them back. A free line
  # changes nothing; with the product on two lines the later one wins. Writes
  # skip validations so a legacy product cannot block the registration. Meant
  # to run inside the registration's transaction.
  class ApplyPurchaseCosts
    def self.call(invoice:)
      new(invoice: invoice).call
    end

    def initialize(invoice:)
      @invoice = invoice
    end

    def call
      @invoice.invoice_items.where("final_unit_cost > 0").order(:id).each do |item|
        product = Product.with_deleted.lock.find(item.product_id)
        now = Time.current
        item.update_columns(previous_cost_unit: product.cost_unit, previous_cost_currency: product.cost_currency,
                            previous_cost_source_id: product.cost_source_invoice_item_id, updated_at: now)
        product.update_columns(cost_unit: item.final_unit_cost, cost_currency: "ARS",
                               cost_source_invoice_item_id: item.id, updated_at: now)
      end

      Result.new(success?: true, record: @invoice, errors: [])
    end
  end
end
