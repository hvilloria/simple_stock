module Web
  module SaleNotes
    class PaymentsController < ApplicationController
      before_action :set_note

      def new
        authorize @note, :collect?, policy_class: SaleNotePolicy
      end

      def create
        authorize @note, :collect?, policy_class: SaleNotePolicy

        result = Payments::CollectSaleNote.call(
          order:            @note,
          discount_percent: params[:discount_percent].to_i,
          tenders:          parsed_tenders
        )

        if result.success?
          redirect_to web_sale_notes_path, notice: "Nota #{@note.paper_number} cobrada"
        else
          flash.now[:alert] = result.errors.join(", ")
          render :new, status: :unprocessable_entity
        end
      end

      private

      def set_note
        @note = Order.immediate.pending.find(params[:sale_note_id])
      end

      # Tenders arrive as `tenders[0][payment_method]=cash&tenders[0][amount]=1.500,00`.
      # Strip Argentine formatting (1.500,00 -> 1500.00) before to_f.
      def parsed_tenders
        rows = params[:tenders]
        return [] if rows.blank?

        rows.to_unsafe_h.values.filter_map do |row|
          raw    = row[:amount].to_s.gsub(".", "").tr(",", ".")
          amount = raw.to_f
          next if amount <= 0
          { payment_method: row[:payment_method], amount: amount }
        end
      end
    end
  end
end
