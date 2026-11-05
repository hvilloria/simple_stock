# frozen_string_literal: true

module Invoices
  # Undoes the cost a purchase set, but only while the product still carries
  # it: a cost typed by hand or set by a newer purchase is kept. The cost goes
  # back to the product's newest purchase on another live invoice or, with
  # none, to what it was before this invoice. Meant to run inside the cancel's
  # transaction, before the invoice is marked cancelled.
  class RevertPurchaseCosts
    def self.call(invoice:)
      new(invoice: invoice).call
    end

    def initialize(invoice:)
      @invoice = invoice
    end

    def call
      costed_items.group_by(&:product_id).each_value do |items|
        revert(items.first, items.last)
      end

      Result.new(success?: true, record: @invoice, errors: [])
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, record: nil, errors: e.record.errors.full_messages)
    end

    private

    def costed_items
      @invoice.invoice_items.where("final_unit_cost > 0").order(:id).to_a
    end

    def revert(first, last)
      product = Product.with_deleted.lock.find(last.product_id)
      return unless product.cost_currency == "ARS" && product.cost_unit == last.final_unit_cost

      previous = newest_other_purchase(product)
      return product.update!(cost_unit: previous.final_unit_cost, cost_currency: "ARS") if previous

      snapshot = live_snapshot(first)
      return if snapshot.previous_cost_currency.blank?

      product.update!(cost_unit: snapshot.previous_cost_unit, cost_currency: snapshot.previous_cost_currency)
    end

    # A snapshot taken while an earlier, since cancelled, purchase held the
    # cost is that purchase's cost: step back to what it replaced instead.
    def live_snapshot(item)
      while item.previous_cost_currency == "ARS" && item.previous_cost_unit&.positive? &&
            (cancelled = cancelled_purchase_behind(item))
        item = cancelled.invoice.invoice_items.where(product_id: item.product_id)
                        .where("final_unit_cost > 0").order(:id).first
      end
      item
    end

    def cancelled_purchase_behind(item)
      InvoiceItem.joins(:invoice)
                 .where(product_id: item.product_id, invoices: { status: "cancelled" })
                 .where("invoice_items.id < ?", item.id)
                 .where(final_unit_cost: item.previous_cost_unit)
                 .order("invoice_items.id DESC")
                 .first
    end

    def newest_other_purchase(product)
      InvoiceItem.joins(:invoice)
                 .where(product_id: product.id)
                 .where.not(invoice_id: @invoice.id)
                 .where.not(invoices: { status: "cancelled" })
                 .where("invoice_items.final_unit_cost > 0")
                 .order("invoices.id DESC, invoice_items.id DESC")
                 .first
    end
  end
end
