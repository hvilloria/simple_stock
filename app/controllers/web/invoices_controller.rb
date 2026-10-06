# frozen_string_literal: true

module Web
  class InvoicesController < ApplicationController
    include CurrencyParser

    before_action :load_suppliers, only: [ :new, :create, :edit, :update ]
    before_action :load_invoice, only: [ :show, :edit, :update, :mark_as_paid, :cancel ]

    def index
      authorize Invoice

      @suppliers = Supplier.alphabetical
      @selected_supplier = Supplier.find_by(id: params[:supplier_id]) if params[:supplier_id].present?
      @status = normalize_status(params[:status])
      @expense_type = params[:expense_type].to_s
      @expense_type_options = Invoice.expense_type_options

      invoices_scope = Invoice.simple_mode
                              .includes(:supplier)
                              .for_supplier(@selected_supplier)
                              .search_invoice(params[:invoice_search])
                              .by_status_filter(@status)
                              .by_expense_type(@expense_type)

      @pagy, @invoices = pagy(ordered_invoices(invoices_scope))

      # Metrics calculated from the model (filtered if applicable)
      metrics_scope = Invoice.simple_mode
                              .pending_payment
                              .for_supplier(@selected_supplier)
                              .search_invoice(params[:invoice_search])
                              .by_expense_type(@expense_type)

      @total_pending_amount = metrics_scope.sum { |i| i.total_amount_ars(include_discount: true) }

      # Available credits (filtered only by supplier, not by invoice search)
      credit_notes_scope = CreditNote.includes(:applied_credits)
                                      .for_supplier(@selected_supplier)
                                      .available

      @total_credit_amount = credit_notes_scope.sum { |cn| cn.remaining_balance_ars }
      # Count only notes with available balance (excludes those already applied/exhausted)
      @credit_notes_count = credit_notes_scope.count(&:available?)

      # Net balance
      @net_balance = @total_pending_amount - @total_credit_amount
    end

    def pending
      authorize Invoice, :view_pending?

      # Selected period
      period = params[:period] || "this_week"
      @selected_period = period

      all_invoices = filter_by_period(period).includes(:supplier).to_a

      @suppliers_with_payments = calculate_payments_by_supplier_unified(all_invoices)

      # Global metrics
      @total_invoices_count = all_invoices.count
      # Original amount (without discounts)
      @total_invoices_amount = all_invoices.sum { |i| i.total_amount_ars }
      # Amount with discounts applied where applicable
      @total_invoices_with_discount = all_invoices.sum { |i| i.amount_with_discount_ars }
      # Total savings from discounts
      @total_savings = all_invoices.sum { |i| i.potential_savings_ars }

      # Available credits (from suppliers that have invoices)
      supplier_ids = all_invoices.map(&:supplier_id).uniq
      @total_credits_amount = CreditNote.where(supplier_id: supplier_ids).available.sum { |cn| cn.remaining_balance_ars }
      @total_credits_count = CreditNote.where(supplier_id: supplier_ids).available.count

      # Total to pay (net) - uses amount with discount
      @total_to_pay = @total_invoices_with_discount - @total_credits_amount
    end

    def show
      authorize @invoice
    end

    def new
      @invoice = Invoice.new(
        currency: "USD",
        purchase_date: Date.current,
        due_date: 30.days.from_now.to_date
      )
      authorize @invoice
    end

    def create
      authorize Invoice, :create?

      result = Invoices::CreateInvoice.call(
        supplier: find_supplier,
        invoice_number: params[:invoice_number],
        amount: parse_amount(params[:amount]),
        currency: params[:currency] || "USD",
        exchange_rate: parse_exchange_rate(params[:exchange_rate], params[:currency]),
        purchase_date: parse_date(params[:purchase_date]),
        due_date: parse_date(params[:due_date]),
        notes: params[:notes],
        early_payment_due_date: parse_optional_date(params[:early_payment_due_date]),
        early_payment_discount_percentage: parse_optional_integer(params[:early_payment_discount_percentage]),
        expense_type: params[:expense_type].presence || "supplier",
        items: submitted_items.map { |item| item.merge(unit_cost: unit_cost_param(item[:unit_cost])) }
      )

      if result.success?
        redirect_to web_invoice_path(result.record), notice: "Factura registrada exitosamente."
      else
        flash.now[:alert] = result.errors.join(", ")
        @submitted_items = submitted_items
        # The form cleans these two fields before posting, so the re-render has
        # to give them back Argentine-formatted or the retry cleans them twice.
        @amount_value        = helpers.number_ar(parse_amount(params[:amount])) if params[:amount].present?
        @exchange_rate_value = helpers.number_ar(parse_amount(params[:exchange_rate])) if params[:exchange_rate].present?
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

      # Parse values in Argentine format
      update_params = invoice_update_params
      # The lines own the amount; a value typed around the read-only field is ignored.
      update_params.delete(:amount) if @invoice.invoice_items.any?
      # The type is locked once lines exist, and an unknown key must not reach the enum.
      if @invoice.invoice_items.any? || !Invoice::EXPENSE_TYPE_LABELS.key?(update_params[:expense_type].to_s)
        update_params.delete(:expense_type)
      end
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

      result = Invoices::PayInvoices.call(
        invoices: [ @invoice ],
        account: params[:account],
        payment_date: parse_date(params[:payment_date]) || Date.current,
        user: current_user
      )

      if result.success?
        redirect_to web_invoice_path(@invoice), notice: payment_notice(result.record)
      else
        redirect_to web_invoice_path(@invoice), alert: result.errors.join(", ")
      end
    end

    def cancel
      authorize @invoice

      result = Invoices::CancelInvoice.call(invoice: @invoice)

      if result.success?
        redirect_to web_invoices_path, notice: "Factura cancelada exitosamente."
      else
        redirect_to web_invoice_path(@invoice), alert: result.errors.join(", ")
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

      result = Invoices::PayInvoices.call(
        invoices: invoices,
        account: params[:account],
        payment_date: parse_date(params[:payment_date]) || Date.current,
        user: current_user,
        credit_note_ids: Array(params[:credit_note_ids])
      )

      if result.success?
        redirect_to pending_web_invoices_path(period: period),
                    notice: "#{invoices.count} factura(s) de #{invoices.first.supplier.name} pagada(s). #{payment_notice(result.record)}"
      else
        redirect_to pending_web_invoices_path(period: period), alert: result.errors.join(", ")
      end
    end

    private

    def load_suppliers
      @suppliers = Supplier.order(:name)
    end

    def payment_notice(movement)
      return "Pagada con notas de crédito: no salió plata." if movement.nil?

      "Salió $ #{helpers.number_ar(movement.amount.abs)} de #{CashMovement.account_label(movement.account)}."
    end

    STATUS_FILTERS = %w[pending paid cancelled].freeze

    def normalize_status(status)
      STATUS_FILTERS.include?(status) ? status : "pending"
    end

    def ordered_invoices(scope)
      @status == "paid" ? scope.by_payment_date : scope.priority_order
    end

    def load_invoice
      @invoice = Invoice.includes(cash_movement: :paid_invoices).find(params[:id])
    end

    def find_supplier
      Supplier.find(params[:supplier_id])
    end

    # Lines arrive as `items[0][product_id]=…&items[0][quantity]=…`. The raw
    # unit cost is kept for the re-render; the service gets the parsed one.
    # Anything that is not a hash of rows is ignored instead of raising.
    def submitted_items
      @submitted_items_memo ||=
        if params[:items].blank? || !params[:items].respond_to?(:to_unsafe_h)
          []
        else
          params[:items].to_unsafe_h.values.filter_map do |row|
            next unless row.is_a?(Hash)

            { product_id: row[:product_id].to_s, sku: row[:sku].to_s, name: row[:name].to_s, brand: row[:brand].to_s,
              quantity: row[:quantity].to_i, unit_cost: row[:unit_cost].to_s }
          end
        end
    end

    # Blank means free; anything that is not a number stays nil so the
    # service refuses it instead of reading it as zero.
    def unit_cost_param(raw)
      return "" if raw.to_s.strip.empty?

      decimal_string_from(raw)
    end

    def parse_date(date_string)
      return Date.current if date_string.blank?
      Date.parse(date_string)
    rescue ArgumentError
      Date.current
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
      # If the currency is ARS, return nil (no exchange rate needed)
      return nil if currency == "ARS"

      # If it is empty or nil, return nil
      return nil if rate_string.blank?

      # Clean Argentine format and convert to float
      parse_amount(rate_string)
    end

    def invoice_update_params
      params.require(:invoice).permit(
        :supplier_id,
        :expense_type,
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

    # Groups invoices by supplier calculating original and discounted amounts
    def calculate_payments_by_supplier_unified(invoices_array)
      invoices_array.group_by(&:supplier)
                    .map do |supplier, supplier_invoices|
                      credit_notes  = supplier.credit_notes.available.to_a.select(&:available?)
                      credits_amount = credit_notes.sum(&:remaining_balance_ars)
                      # Original amount (without discount)
                      invoices_amount = supplier_invoices.sum { |i| i.total_amount }
                      # Amount with discount applied where applicable
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
