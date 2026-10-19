# frozen_string_literal: true

module Web
  class PaymentsController < ApplicationController
    before_action :set_payment, except: :index

    PERIOD_OPTIONS = [
      [ "Hoy", "today" ],
      [ "Ayer", "yesterday" ],
      [ "Últimos 7 días", "last_7_days" ],
      [ "Este mes", "this_month" ],
      [ "Rango", "custom" ]
    ].freeze
    STATUS_OPTIONS = [ [ "Vigentes", "active" ], [ "Anulados", "voided" ], [ "Todos", "all" ] ].freeze

    def index
      authorize Payment

      @search = params[:q].to_s.strip
      @period = PERIOD_OPTIONS.map(&:last).include?(params[:period]) ? params[:period] : "today"
      @status = ::Payments::IndexQuery::STATUSES.include?(params[:status]) ? params[:status] : "active"
      @payment_method = params[:payment_method].to_s
      @from, @to = @search.present? ? [ nil, nil ] : resolve_period

      query = ::Payments::IndexQuery.new(from: @from, to: @to, payment_method: @payment_method,
                                         status: @status, search: @search)
      @totals = query.totals_by_method
      @pagy, @payments = pagy(query.relation)
    end

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

    def resolve_period
      today = Date.current
      case @period
      when "yesterday"   then [ today - 1, today - 1 ]
      when "last_7_days" then [ today - 6, today ]
      when "this_month"  then [ today.beginning_of_month, today ]
      when "custom"      then custom_range || [ today, today ]
      else [ today, today ]
      end
    end

    def custom_range
      from = parse_date(params[:from])
      to   = parse_date(params[:to])
      [ from, to ] if from && to && from <= to
    end

    def parse_date(value)
      Date.iso8601(value.to_s)
    rescue Date::Error
      nil
    end

    def set_payment
      @payment = Payment.includes(:customer, :voided_by, allocations: :order, voided_allocations: :order,
                                  cash_movements: :user).find(params[:id])
    end

    def render_show(open:, type: @payment.invoice_type, number: @payment.invoice_number, status: :ok)
      @form_open      = open
      @invoice_type   = type
      @invoice_number = number
      render :show, status: status
    end
  end
end
