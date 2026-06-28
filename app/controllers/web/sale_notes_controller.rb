module Web
  class SaleNotesController < ApplicationController
    def index
      authorize Order, :index?, policy_class: SaleNotePolicy
      @pagy, @notes = pagy(
        Order.immediate.pending
             .includes(:customer, order_items: :product)
             .order(created_at: :desc)
      )
    end

    def cancel
      @note = Order.find(params[:id])
      authorize @note, :cancel?, policy_class: SaleNotePolicy

      result = Sales::CancelOrder.call(order: @note, reason: "Cancelada desde caja")

      if result.success?
        redirect_to web_sale_notes_path, notice: "Nota ##{@note.id} cancelada"
      else
        redirect_to web_sale_notes_path, alert: result.errors.join(", ")
      end
    end
  end
end
