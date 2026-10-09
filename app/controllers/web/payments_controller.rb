# frozen_string_literal: true

module Web
  class PaymentsController < ApplicationController
    before_action :set_payment

    def show
      authorize @payment
      render_show(open: params[:facturar].present?)
    end

    def update
      authorize @payment

      result = ::Payments::AssignInvoice.call(
        payment:        @payment,
        invoice_type:   params[:invoice_type],
        invoice_number: params[:invoice_number]
      )

      if result.success?
        redirect_to web_payment_path(@payment), notice: "Factura guardada"
      else
        @error = result.errors.join(", ")
        render_show(open: true, type: params[:invoice_type], number: params[:invoice_number],
                    status: :unprocessable_entity)
      end
    end

    def change_method
      authorize @payment, :change_method?

      result = ::Payments::ChangeMethod.call(payment: @payment, payment_method: params[:payment_method])

      if result.success?
        redirect_to web_payment_path(@payment), notice: "Medio de pago actualizado"
      else
        @payment.reload
        @method_error = result.errors.join(", ")
        render_show(open: false, status: :unprocessable_entity)
      end
    end

    private

    def set_payment
      @payment = Payment.includes(:customer, allocations: :order, cash_movements: :user).find(params[:id])
    end

    def render_show(open:, type: @payment.invoice_type, number: @payment.invoice_number, status: :ok)
      @form_open      = open
      @invoice_type   = type
      @invoice_number = number
      render :show, status: status
    end
  end
end
