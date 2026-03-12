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

      @total_credit_amount = credit_notes_scope.sum { |cn| cn.remaining_balance_ars }
      @credit_notes_count = credit_notes_scope.count

      # Balance neto
      @net_balance = @total_pending_amount - @total_credit_amount
    end

    def pending
      authorize Invoice, :view_pending?

      # Período seleccionado
      period = params[:period] || "this_week"
      @selected_period = period

      all_invoices = filter_by_period(period).includes(:supplier).to_a

      @suppliers_with_payments = calculate_payments_by_supplier_unified(all_invoices)

      # Métricas globales
      @total_invoices_count = all_invoices.count
      # Monto original (sin descuentos)
      @total_invoices_amount = all_invoices.sum { |i| i.total_amount_ars }
      # Monto con descuentos aplicados donde corresponda
      @total_invoices_with_discount = all_invoices.sum { |i| i.amount_with_discount_ars }
      # Ahorro total por descuentos
      @total_savings = all_invoices.sum { |i| i.potential_savings_ars }

      # Créditos disponibles (de proveedores que tienen facturas)
      supplier_ids = all_invoices.map(&:supplier_id).uniq
      @total_credits_amount = CreditNote.where(supplier_id: supplier_ids).available.sum { |cn| cn.remaining_balance_ars }
      @total_credits_count = CreditNote.where(supplier_id: supplier_ids).available.count

      # Total a pagar (neto) - usa monto con descuento
      @total_to_pay = @total_invoices_with_discount - @total_credits_amount
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
        notes: params[:notes],
        early_payment_due_date: parse_optional_date(params[:early_payment_due_date]),
        early_payment_discount_percentage: parse_optional_integer(params[:early_payment_discount_percentage])
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
      apply_discount = params[:apply_discount] == "true"

      # Validar descuento
      if apply_discount && !@invoice.eligible_for_discount?(payment_date)
        redirect_to web_invoice_path(@invoice),
                    alert: "El descuento ya expiró. No se puede aplicar."
        return
      end

      result = Invoices::MarkAsPaid.call(
        invoice: @invoice,
        payment_date: payment_date,
        apply_discount: apply_discount
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

      period       = params[:period] || "this_week"
      invoice_ids  = Array(params[:invoice_ids]).map(&:to_i).reject(&:zero?)
      invoices     = Invoice.where(id: invoice_ids).to_a

      if invoices.empty?
        redirect_to pending_web_invoices_path(period: period), alert: "No se recibieron facturas para pagar."
        return
      end

      payment_date = params[:payment_date].present? ? Date.parse(params[:payment_date]) : Date.current

      credit_note_ids = Array(params[:credit_note_ids]).map(&:to_i).reject(&:zero?)

      result = Invoices::ProcessPayment.call(
        invoices:        invoices,
        credit_note_ids: credit_note_ids,
        payment_date:    payment_date
      )

      supplier_name = invoices.first&.supplier&.name

      if result.success?
        redirect_to pending_web_invoices_path(period: period),
                    notice: "#{invoices.count} factura(s) de #{supplier_name} marcada(s) como pagada(s)."
      else
        redirect_to pending_web_invoices_path(period: period), alert: result.errors.join(", ")
      end
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

    def parse_optional_date(date_string)
      return nil if date_string.blank?
      Date.parse(date_string)
    rescue ArgumentError
      nil
    end

    def parse_optional_integer(value)
      return nil if value.blank?
      value.to_i
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
        :early_payment_due_date,
        :early_payment_discount_percentage,
        :notes
      )
    end

    def filter_by_period(period)
      case period
      when "this_week"
        start_date = Date.current.beginning_of_week(:monday)
        end_date   = Date.current.end_of_week(:monday)
      when "next_week"
        start_date = (Date.current + 1.week).beginning_of_week(:monday)
        end_date   = (Date.current + 1.week).end_of_week(:monday)
      when "this_month"
        start_date = Date.current.beginning_of_month
        end_date   = Date.current.end_of_month
      when "next_month"
        start_date = (Date.current + 1.month).beginning_of_month
        end_date   = (Date.current + 1.month).end_of_month
      when "overdue"
        return Invoice.overdue
      else
        start_date = Date.current.beginning_of_week(:monday)
        end_date   = Date.current.end_of_week(:monday)
      end
      Invoice.due_or_discount_in_period(start_date, end_date)
    end

    def calculate_payments_by_supplier(invoices)
      invoices.includes(:supplier)
              .group_by(&:supplier)
              .map do |supplier, supplier_invoices|
                credits_amount = supplier.credit_notes.available.sum { |cn| cn.remaining_balance_ars }
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

    def calculate_payments_by_supplier_from_array(invoices_array)
      invoices_array.group_by(&:supplier)
                    .map do |supplier, supplier_invoices|
                      credits_amount = supplier.credit_notes.available.sum { |cn| cn.remaining_balance_ars }
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

    # Agrupa facturas por proveedor calculando montos originales y con descuento
    def calculate_payments_by_supplier_unified(invoices_array)
      invoices_array.group_by(&:supplier)
                    .map do |supplier, supplier_invoices|
                      credit_notes  = supplier.credit_notes.available.to_a.select(&:available?)
                      credits_amount = credit_notes.sum(&:remaining_balance_ars)
                      # Monto original (sin descuento)
                      invoices_amount = supplier_invoices.sum { |i| i.total_amount }
                      # Monto con descuento aplicado donde corresponda
                      invoices_amount_with_discount = supplier_invoices.sum { |i| i.amount_with_discount_ars }

                      {
                        supplier: supplier,
                        invoices: supplier_invoices,
                        invoices_count: supplier_invoices.count,
                        invoices_amount: invoices_amount,
                        invoices_amount_with_discount: invoices_amount_with_discount,
                        credits_amount: credits_amount,
                        credit_notes: credit_notes,
                        amount_to_pay: invoices_amount_with_discount - credits_amount
                      }
                    end
                    .sort_by { |data| data[:amount_to_pay] }
                    .reverse
    end
  end
end
