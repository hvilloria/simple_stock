# frozen_string_literal: true

module Web
  class CreditNotesController < ApplicationController
    include CurrencyParser

    before_action :load_credit_note, only: [ :show, :edit, :update, :destroy, :mark_as_applied ]
    before_action :load_suppliers, only: [ :new, :create, :edit, :update ]

    def index
      authorize CreditNote

      @suppliers = Supplier.alphabetical
      @selected_supplier = Supplier.find_by(id: params[:supplier_id]) if params[:supplier_id].present?

      @credit_notes = CreditNote.includes(:supplier, :invoice)
                                .for_supplier(@selected_supplier)
                                .search_number(params[:search])
                                .by_status(params[:status])
                                .recent
                                .limit(50)

      @total_credit_amount = @credit_notes.sum { |cn| cn.total_amount_ars }
      @credit_notes_count = @credit_notes.count
      @selected_status = params[:status]
    end

    def show
      authorize @credit_note
    end

    def new
      @credit_note = CreditNote.new(
        currency: "ARS",
        issue_date: Date.today
      )

      # Pre-cargar factura si viene del parámetro
      if params[:invoice_id].present?
        invoice = Invoice.find(params[:invoice_id])
        @credit_note.invoice = invoice
        @credit_note.supplier = invoice.supplier
        @credit_note.currency = invoice.currency
        @credit_note.exchange_rate = invoice.exchange_rate
      end

      authorize @credit_note
    end

    def create
      @credit_note = CreditNote.new(credit_note_params)
      @credit_note.amount = parse_amount(params[:credit_note][:amount])
      @credit_note.exchange_rate = parse_amount(params[:credit_note][:exchange_rate]) if params[:credit_note][:exchange_rate].present?

      authorize @credit_note

      if @credit_note.save
        redirect_to web_credit_note_path(@credit_note), notice: "Nota de crédito registrada exitosamente."
      else
        load_suppliers
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      authorize @credit_note
    end

    def update
      authorize @credit_note

      update_params = credit_note_params
      update_params[:amount] = parse_amount(params[:credit_note][:amount]) if params[:credit_note][:amount].present?
      update_params[:exchange_rate] = parse_amount(params[:credit_note][:exchange_rate]) if params[:credit_note][:exchange_rate].present?

      if @credit_note.update(update_params)
        redirect_to web_credit_note_path(@credit_note), notice: "Nota de crédito actualizada exitosamente."
      else
        load_suppliers
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      authorize @credit_note

      if @credit_note.destroy
        redirect_to web_credit_notes_path, notice: "Nota de crédito eliminada exitosamente."
      else
        redirect_to web_credit_note_path(@credit_note), alert: "No se pudo eliminar la nota de crédito."
      end
    end

    def mark_as_applied
      authorize @credit_note, :update?
      
      unless @credit_note.pending_status?
        redirect_to web_credit_note_path(@credit_note), 
                    alert: "Esta nota de crédito ya fue aplicada."
        return
      end
      
      if @credit_note.update(status: "applied", applied_at: Date.current)
        redirect_to web_credit_note_path(@credit_note), 
                    notice: "Nota de crédito marcada como aplicada."
      else
        redirect_to web_credit_note_path(@credit_note), 
                    alert: "Error al marcar la nota de crédito."
      end
    end

    def supplier_invoices
      authorize CreditNote, :index?
      
      supplier = Supplier.find_by(id: params[:supplier_id])
      
      if supplier
        invoices = supplier.invoices.simple_mode.pending_payment.order(due_date: :asc)
        render json: invoices.map { |inv| { id: inv.id, number: inv.invoice_number, amount: inv.total_amount_ars } }
      else
        render json: []
      end
    end

    private

    def load_credit_note
      @credit_note = CreditNote.find(params[:id])
    end

    def load_suppliers
      @suppliers = Supplier.alphabetical
      @invoices = if @credit_note&.supplier
                    @credit_note.supplier.invoices.simple_mode.pending_payment.order(due_date: :asc)
                  else
                    []
                  end
    end

    def credit_note_params
      params.require(:credit_note).permit(
        :supplier_id,
        :invoice_id,
        :credit_note_number,
        :amount,
        :currency,
        :exchange_rate,
        :issue_date,
        :notes
      )
    end
  end
end
