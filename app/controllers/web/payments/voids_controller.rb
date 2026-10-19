# frozen_string_literal: true

module Web
  module Payments
    class VoidsController < ApplicationController
      before_action :set_payment

      def new
        authorize @payment, :void?
        @cascade = ::Payments::VoidCascade.call(payment: @payment)
      end

      def create
        authorize @payment, :void?

        result = ::Payments::Void.call(payment: @payment, user: current_user,
                                       reason: params[:reason], payment_ids: params[:payment_ids])

        if result.success?
          count = result.record.size
          redirect_to web_payment_path(@payment), notice: count == 1 ? "Cobro anulado" : "#{count} cobros anulados"
        else
          @error = result.errors.join(", ")
          @reason = params[:reason]
          @cascade = ::Payments::VoidCascade.call(payment: @payment.reload)
          render :new, status: :unprocessable_entity
        end
      end

      private

      def set_payment
        @payment = Payment.find(params[:payment_id])
      end
    end
  end
end
