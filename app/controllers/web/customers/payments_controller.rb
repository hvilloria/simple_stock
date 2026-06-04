# frozen_string_literal: true

module Web
  module Customers
    class PaymentsController < ApplicationController
      before_action :set_customer

      def new
        authorize Payment.new(customer: @customer), :new?
        @pending_orders = @customer.orders
                                    .credit
                                    .where(status: %w[pending confirmed])
                                    .includes(:payment_allocations)
                                    .order(:created_at)
                                    .select { |o| o.outstanding_balance > 0 }
      end

      def create
        authorize Payment.new(customer: @customer), :new?

        result = Payments::AllocatePayment.call(
          customer: @customer,
          payment_date: params[:payment_date].presence || Date.current,
          notes: params[:notes],
          allocations: parsed_allocations
        )

        if result.success?
          total = result.record.sum(&:amount)
          orders_count = result.record.sum { |p| p.allocations.size }
          redirect_to web_customer_path(@customer),
                      notice: "Cobro de $#{total.to_i} registrado sobre #{orders_count} #{'orden'.pluralize(orders_count)}."
        else
          @pending_orders = @customer.orders
                                      .credit
                                      .where(status: %w[pending confirmed])
                                      .includes(:payment_allocations)
                                      .order(:created_at)
                                      .select { |o| o.outstanding_balance > 0 }
          flash.now[:alert] = result.errors.join(", ")
          render :new, status: :unprocessable_entity
        end
      end

      private

      def set_customer
        @customer = Customer.find(params[:customer_id])
      end

      def parsed_allocations
        rows = params[:allocations]
        return [] if rows.blank?

        rows.to_unsafe_h.values.filter_map do |row|
          next if row[:include] != "1"
          next if row[:amount].blank? || row[:amount].to_f <= 0

          discounts_hash =
            if row[:discounts].respond_to?(:to_unsafe_h)
              row[:discounts].to_unsafe_h
            else
              row[:discounts] || {}
            end

          {
            order_id: row[:order_id],
            amount: row[:amount].to_f,
            payment_method: row[:payment_method],
            item_discounts: discounts_hash.transform_values { |v| v.to_f }
          }
        end
      end
    end
  end
end
