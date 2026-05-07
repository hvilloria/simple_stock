# frozen_string_literal: true

module Web
  module Customers
    class PaymentsController < ApplicationController
      before_action :set_customer

      def new
        @payment = Payment.new
        authorize @payment
      end

      def create
        authorize Payment.new(customer: @customer)
        result = Payments::RegisterPayment.call(
          customer: @customer,
          amount: payment_params[:amount],
          payment_method: payment_params[:payment_method],
          payment_date: payment_params[:payment_date],
          notes: payment_params[:notes]
        )
        if result.success?
          redirect_to web_customer_path(@customer), notice: "Pago registrado exitosamente."
        else
          @payment = Payment.new(payment_params)
          flash.now[:alert] = result.errors.join(", ")
          render :new, status: :unprocessable_entity
        end
      end

      private

      def set_customer
        @customer = Customer.find(params[:customer_id])
      end

      def payment_params
        params.require(:payment).permit(:amount, :payment_method, :payment_date, :notes)
      end
    end
  end
end
