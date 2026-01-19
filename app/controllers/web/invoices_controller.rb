# frozen_string_literal: true

module Web
  class InvoicesController < ApplicationController
    include CurrencyParser

    before_action :load_suppliers, only: [ :new, :create, :edit, :update ]
    before_action :load_invoice, only: [ :show, :edit, :update, :mark_as_paid, :cancel ]

    def index
      authorize Invoice

      # Cargar proveedores para el filtro
      @suppliers = Supplier.alphabetical

      # Filtrar por supplier_id si está presente
      @selected_supplier = Supplier.find_by(id: params[:supplier_id]) if params[:supplier_id].present?

      # Scope base con filtros opcionales (proveedor + búsqueda)
      invoices_scope = Invoice.simple_mode
                                .includes(:supplier)
                                .for_supplier(@selected_supplier)
                                .search_invoice(params[:invoice_search])

      @invoices = invoices_scope.priority_order.limit(50)

      # Métricas calculadas desde el modelo (filtradas si aplica)
      metrics_scope = Invoice.simple_mode
                              .pending_payment
                              .for_supplier(@selected_supplier)
                              .search_invoice(params[:invoice_search])

      @total_pending_amount = metrics_scope.sum { |i| i.total_amount_ars }

      # Créditos disponibles (filtrados solo por proveedor, no por búsqueda de invoice)
      credit_notes_scope = CreditNote.includes(:supplier)
                                      .for_supplier(@selected_supplier)
                                      .available

      @total_credit_amount = credit_notes_scope.sum { |cn| cn.total_amount_ars }
      @credit_notes_count = credit_notes_scope.count

      # Balance neto
      @net_balance = @total_pending_amount - @total_credit_amount
    end

    def pending
      authorize Invoice, :view_pending?

      # Filtrar facturas según período seleccionado
      period = params[:period] || "this_week"
      @invoices = filter_by_period(period)

      # Agrupar por proveedor con cálculos
      @suppliers_with_payments = calculate_payments_by_supplier(@invoices)

      # Métricas globales
      @total_invoices_amount = @invoices.sum { |i| i.total_amount_ars }
      @total_invoices_count = @invoices.count

      # Créditos disponibles (de proveedores que tienen facturas en este período)
      supplier_ids = @invoices.pluck(:supplier_id).uniq
      @total_credits_amount = CreditNote.where(supplier_id: supplier_ids).available.sum { |cn| cn.total_amount_ars }
      @total_credits_count = CreditNote.where(supplier_id: supplier_ids).available.count

      # Total a pagar (neto)
      @total_to_pay = @total_invoices_amount - @total_credits_amount

      # Guardar período seleccionado para la vista
      @selected_period = period
    end

    def show
      authorize @invoice
    end

    def new
      @invoice = Invoice.new(
        currency: "USD",
        purchase_date: Date.today,
        due_date: 30.days.from_now.to_date
      )
      authorize @invoice
    end

    def create
      authorize Invoice, :create?

      result = Invoices::CreateSimpleInvoice.call(
        supplier: find_supplier,
        invoice_number: params[:invoice_number],
        amount: parse_amount(params[:amount]),
        currency: params[:currency] || "USD",
        exchange_rate: parse_exchange_rate(params[:exchange_rate], params[:currency]),
        purchase_date: parse_date(params[:purchase_date]),
        due_date: parse_date(params[:due_date]),
        notes: params[:notes]
      )

      if result.success?
        redirect_to web_invoice_path(result.record), notice: "Factura registrada exitosamente."
      else
        flash.now[:alert] = result.errors.join(", ")
        @invoice = Invoice.new
        load_suppliers
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      authorize @invoice

      unless @invoice.pending_status?
        redirect_to web_invoice_path(@invoice), alert: "Solo se pueden editar facturas pendientes."
        nil
      end
    end

    def update
      authorize @invoice

      unless @invoice.pending_status?
        redirect_to web_invoice_path(@invoice), alert: "Solo se pueden editar facturas pendientes."
        return
      end

      # Parsear valores con formato argentino
      update_params = invoice_update_params
      update_params[:amount] = parse_amount(update_params[:amount]) if update_params[:amount].present?
      update_params[:exchange_rate] = parse_amount(update_params[:exchange_rate]) if update_params[:exchange_rate].present?

      if @invoice.update(update_params)
        redirect_to web_invoice_path(@invoice), notice: "Factura actualizada exitosamente."
      else
        load_suppliers
        render :edit, status: :unprocessable_entity
      end
    end

    def mark_as_paid
      authorize @invoice

      payment_date = parse_date(params[:payment_date]) || Date.today

      result = Invoices::MarkAsPaid.call(
        invoice: @invoice,
        payment_date: payment_date
      )

      if result.success?
        redirect_to web_invoice_path(@invoice), notice: "Factura marcada como pagada."
      else
        redirect_to web_invoice_path(@invoice), alert: result.errors.join(", ")
      end
    end

    def cancel
      authorize @invoice

      unless @invoice.pending_status?
        redirect_to web_invoice_path(@invoice), alert: "Solo se pueden cancelar facturas pendientes."
        return
      end

      if @invoice.update(status: "cancelled")
        redirect_to web_invoices_path, notice: "Factura cancelada exitosamente."
      else
        redirect_to web_invoice_path(@invoice), alert: "Error al cancelar la factura."
      end
    end

    def mark_supplier_paid
      authorize Invoice, :mark_supplier_paid?

      supplier = Supplier.find(params[:supplier_id])
      period = params[:period] || "this_week"

      # Obtener facturas del período para este proveedor
      invoices = filter_by_period(period).where(supplier: supplier)

      if invoices.empty?
        redirect_to pending_web_invoices_path(period: period),
                    alert: "No hay facturas pendientes para #{supplier.name} en este período."
        return
      end

      # Guardar count antes de marcar como pagadas
      invoices_count = invoices.count
      payment_date = params[:payment_date] ? Date.parse(params[:payment_date]) : Date.current

      # Marcar todas como pagadas
      invoices.each do |invoice|
        invoice.mark_as_paid!(payment_date)
      end

      redirect_to pending_web_invoices_path(period: period),
                  notice: "#{invoices_count} factura(s) de #{supplier.name} marcada(s) como pagada(s)."
    end

    private

    def load_suppliers
      @suppliers = Supplier.order(:name)
    end

    def load_invoice
      @invoice = Invoice.find(params[:id])
    end

    def find_supplier
      Supplier.find(params[:supplier_id])
    end

    def parse_date(date_string)
      return Date.today if date_string.blank?
      Date.parse(date_string)
    rescue ArgumentError
      Date.today
    end

    def parse_exchange_rate(rate_string, currency)
      # Si la moneda es ARS, retornar nil (no se necesita tipo de cambio)
      return nil if currency == "ARS"

      # Si está vacío o es nil, retornar nil
      return nil if rate_string.blank?

      # Limpiar formato argentino y convertir a float
      parse_amount(rate_string)
    end

    def invoice_update_params
      params.require(:invoice).permit(
        :supplier_id,
        :invoice_number,
        :amount,
        :exchange_rate,
        :purchase_date,
        :due_date,
        :notes
      )
    end

    def filter_by_period(period)
      case period
      when "this_week"
        Invoice.due_this_week
      when "next_week"
        Invoice.due_next_week
      when "this_month"
        Invoice.due_this_month
      when "next_month"
        Invoice.due_next_month
      when "overdue"
        Invoice.overdue
      else
        Invoice.due_this_week
      end
    end

    def calculate_payments_by_supplier(invoices)
      invoices.includes(:supplier)
              .group_by(&:supplier)
              .map do |supplier, supplier_invoices|
                credits_amount = supplier.credit_notes.available.sum { |cn| cn.total_amount_ars }
                invoices_amount = supplier_invoices.sum { |i| i.total_amount_ars }

                {
                  supplier: supplier,
                  invoices: supplier_invoices,
                  invoices_count: supplier_invoices.count,
                  invoices_amount: invoices_amount,
                  credits_amount: credits_amount,
                  amount_to_pay: invoices_amount - credits_amount
                }
              end
              .sort_by { |data| data[:amount_to_pay] }
              .reverse
    end
  end
end
