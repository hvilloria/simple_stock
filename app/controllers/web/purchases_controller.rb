# frozen_string_literal: true

module Web
  class PurchasesController < ApplicationController
    before_action :load_suppliers, only: [ :new, :create, :edit, :update ]
    before_action :load_purchase, only: [ :show, :edit, :update, :mark_as_paid, :cancel ]

    def index
      authorize Purchase
      @purchases = Purchase.simple_mode
                          .includes(:supplier)
                          .order(status: :desc)
                          .limit(50)

      # Métricas para las cards
      @total_pending_amount = calculate_total_pending_amount
      @due_today_purchases = Purchase.due_today.includes(:supplier)
      @due_this_week_purchases = Purchase.due_this_week.includes(:supplier)
    end

    def show
      authorize @purchase
    end

    def new
      @purchase = Purchase.new(
        currency: "USD",
        purchase_date: Date.today,
        due_date: 30.days.from_now.to_date
      )
      authorize @purchase
    end

    def create
      authorize Purchase, :create?

      result = Purchases::CreateSimplePurchase.call(
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
        redirect_to web_purchase_path(result.record), notice: "Factura registrada exitosamente."
      else
        flash.now[:alert] = result.errors.join(", ")
        @purchase = Purchase.new
        load_suppliers
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      authorize @purchase

      unless @purchase.pending_status?
        redirect_to web_purchase_path(@purchase), alert: "Solo se pueden editar facturas pendientes."
        nil
      end
    end

    def update
      authorize @purchase

      unless @purchase.pending_status?
        redirect_to web_purchase_path(@purchase), alert: "Solo se pueden editar facturas pendientes."
        return
      end

      # Parsear valores con formato argentino
      update_params = purchase_update_params
      update_params[:amount] = parse_amount(update_params[:amount]) if update_params[:amount].present?
      update_params[:exchange_rate] = parse_amount(update_params[:exchange_rate]) if update_params[:exchange_rate].present?

      if @purchase.update(update_params)
        redirect_to web_purchase_path(@purchase), notice: "Factura actualizada exitosamente."
      else
        load_suppliers
        render :edit, status: :unprocessable_entity
      end
    end

    def mark_as_paid
      authorize @purchase

      payment_date = parse_date(params[:payment_date]) || Date.today

      result = Purchases::MarkAsPaid.call(
        purchase: @purchase,
        payment_date: payment_date
      )

      if result.success?
        redirect_to web_purchase_path(@purchase), notice: "Factura marcada como pagada."
      else
        redirect_to web_purchase_path(@purchase), alert: result.errors.join(", ")
      end
    end

    def cancel
      authorize @purchase

      unless @purchase.pending_status?
        redirect_to web_purchase_path(@purchase), alert: "Solo se pueden cancelar facturas pendientes."
        return
      end

      if @purchase.update(status: "cancelled")
        redirect_to web_purchases_path, notice: "Factura cancelada exitosamente."
      else
        redirect_to web_purchase_path(@purchase), alert: "Error al cancelar la factura."
      end
    end

    private

    def load_suppliers
      @suppliers = Supplier.order(:name)
    end

    def load_purchase
      @purchase = Purchase.find(params[:id])
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

    def parse_amount(amount_string)
      return nil if amount_string.blank?

      # Limpiar formato argentino: remover puntos (miles) y cambiar coma por punto (decimal)
      # "1.500.000,50" → "1500000.50"
      cleaned = amount_string.to_s.gsub(/\./, "").gsub(/,/, ".")
      cleaned.to_f
    end

    def parse_exchange_rate(rate_string, currency)
      # Si la moneda es ARS, retornar nil (no se necesita tipo de cambio)
      return nil if currency == "ARS"

      # Si está vacío o es nil, retornar nil
      return nil if rate_string.blank?

      # Limpiar formato argentino y convertir a float
      parse_amount(rate_string)
    end

    def purchase_update_params
      params.require(:purchase).permit(
        :supplier_id,
        :invoice_number,
        :amount,
        :exchange_rate,
        :purchase_date,
        :due_date,
        :notes
      )
    end

    def calculate_total_pending_amount
      Purchase.simple_mode
              .where(status: "pending")
              .sum { |p| p.total_amount_ars }
    end
  end
end
