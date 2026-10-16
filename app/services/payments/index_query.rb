# frozen_string_literal: true

module Payments
  # The collections list. A search looks at the notes a payment covers or
  # covered and at the customer, across the whole history when no period is
  # given. Totals only ever count active payments.
  class IndexQuery
    STATUSES = %w[active voided all].freeze

    def initialize(from:, to:, payment_method: nil, status: "active", search: nil)
      @from           = from
      @to             = to
      @payment_method = payment_method.to_s
      @status         = STATUSES.include?(status.to_s) ? status.to_s : "active"
      @search         = search.to_s.strip
    end

    def relation
      by_status(scoped)
        .includes(:customer, allocations: :order, voided_allocations: :order)
        .order(payment_date: :desc, id: :desc)
    end

    def totals_by_method
      scoped.active_status.group(:payment_method).sum(:amount)
    end

    private

    def scoped
      payments = Payment.all
      payments = payments.where(payment_date: @from..@to) if @from && @to
      payments = payments.where(payment_method: @payment_method) if Payment::PAYMENT_METHODS.include?(@payment_method)
      payments = payments.where(id: matching_ids) if @search.present?
      payments
    end

    def by_status(payments)
      case @status
      when "voided" then payments.voided_status
      when "all"    then payments
      else payments.active_status
      end
    end

    def matching_ids
      pattern = "%#{Payment.sanitize_sql_like(@search)}%"
      orders = Order.where("orders.paper_number ILIKE :p OR unaccent(COALESCE(orders.contact_name, '')) ILIKE unaccent(:p)",
                           p: pattern).select(:id)
      customers = Customer.where("unaccent(customers.name) ILIKE unaccent(?)", pattern).select(:id)

      Payment.where(customer_id: customers)
             .or(Payment.where(id: PaymentAllocation.where(order_id: orders).select(:payment_id)))
             .or(Payment.where(id: VoidedPaymentAllocation.where(order_id: orders).select(:payment_id)))
             .select(:id)
    end
  end
end
