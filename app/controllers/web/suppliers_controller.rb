# frozen_string_literal: true

module Web
  class SuppliersController < ApplicationController
    before_action :load_supplier, only: [ :show, :edit, :update, :destroy ]

    def index
      authorize Supplier
      @suppliers = Supplier.alphabetical
    end

    def show
      authorize @supplier
      @pending_invoices = @supplier.invoices.simple_mode.pending_payment.order(due_date: :asc)
      @paid_invoices = @supplier.invoices.simple_mode.paid_invoices.order(paid_at: :desc).limit(10)
    end

    def new
      @supplier = Supplier.new
      authorize @supplier
    end

    def create
      @supplier = Supplier.new(supplier_params)
      authorize @supplier

      if @supplier.save
        redirect_to web_suppliers_path, notice: "Proveedor creado exitosamente."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      authorize @supplier
    end

    def update
      authorize @supplier

      # No permitir cambiar el nombre
      update_params = supplier_params.except(:name)

      if @supplier.update(update_params)
        redirect_to web_supplier_path(@supplier), notice: "Proveedor actualizado exitosamente."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      authorize @supplier

      if @supplier.destroy
        redirect_to web_suppliers_path, notice: "Proveedor eliminado exitosamente."
      else
        redirect_to web_suppliers_path, alert: "No se puede eliminar el proveedor porque tiene facturas asociadas."
      end
    end

    private

    def load_supplier
      @supplier = Supplier.find(params[:id])
    end

    def supplier_params
      params.require(:supplier).permit(
        :name,
        :email,
        :phone,
        :cuit,
        :bank_alias,
        :bank_account,
        :payment_term_days
      )
    end
  end
end
