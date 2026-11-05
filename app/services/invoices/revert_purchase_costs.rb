# frozen_string_literal: true

module Invoices
  # Undoes the cost a purchase set, but only while one of its lines is still
  # the product's cost source: a hand cost or a newer purchase is kept. It
  # follows each line's previous source back past cancelled purchases and
  # restores the first hand, legacy or live-purchase cost it reaches. Meant to
  # run inside the cancel's transaction, before the invoice is marked cancelled.
  class RevertPurchaseCosts
    def self.call(invoice:)
      new(invoice: invoice).call
    end

    def initialize(invoice:)
      @invoice = invoice
    end

    def call
      @invoice.invoice_items.where("final_unit_cost > 0").distinct.pluck(:product_id).sort.each do |product_id|
        revert(Product.with_deleted.lock.find(product_id))
      end

      Result.new(success?: true, record: @invoice, errors: [])
    end

    private

    def revert(product)
      source = product.cost_source_invoice_item
      return unless source&.invoice_id == @invoice.id

      source = source.previous_cost_source while undone?(source.previous_cost_source)
      product.update_columns(**restored_cost(source), updated_at: Time.current)
    end

    def restored_cost(item)
      return { cost_unit: nil, cost_source_invoice_item_id: nil } if item.previous_cost_currency.blank?

      { cost_unit: item.previous_cost_unit, cost_currency: item.previous_cost_currency,
        cost_source_invoice_item_id: item.previous_cost_source_id }
    end

    def undone?(item)
      item.present? && (item.invoice_id == @invoice.id || item.invoice.cancelled_status?)
    end
  end
end
