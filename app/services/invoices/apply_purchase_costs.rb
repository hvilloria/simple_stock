# frozen_string_literal: true

module Invoices
  # A registered purchase sets each product's cost to the line's final unit
  # cost in pesos, keeping the cost it replaced on the line so a cancel can put
  # it back. A free line changes nothing; with the product on two lines the
  # later one wins. Meant to run inside the registration's transaction.
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
        item.update!(previous_cost_unit: product.cost_unit, previous_cost_currency: product.cost_currency)
        product.update!(cost_unit: item.final_unit_cost, cost_currency: "ARS")
      end

      Result.new(success?: true, record: @invoice, errors: [])
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, record: nil, errors: e.record.errors.full_messages)
    end
  end
end
