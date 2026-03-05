# frozen_string_literal: true

module Invoices
  # Processes payment for one or more simple-mode invoices from the same supplier.
  # Optionally applies credit notes (partial or full) before marking invoices as paid.
  #
  # Usage:
  #   Invoices::ProcessPayment.call(
  #     invoices:            [invoice1, invoice2],
  #     credit_applications: [
  #       { credit_note_id: 1, invoice_id: 5, amount: 10_000 },
  #       { credit_note_id: 1, invoice_id: 6, amount: 20_000 },
  #     ],
  #     payment_date:        Date.today
  #   )
  class ProcessPayment
    def self.call(**params)
      new(**params).call
    end

    # credit_applications: [{credit_note_id:, invoice_id:, amount:}] — pre-distributed (used by specs)
    # credit_note_ids:     [Integer]                                  — CN ids only (used by controller)
    def initialize(invoices:, credit_applications: [], credit_note_ids: [], payment_date: Date.today)
      @invoices       = Array(invoices)
      @payment_date   = payment_date
      @credit_applications = if credit_note_ids.any?
                               distribute_credits(credit_note_ids)
                             else
                               credit_applications
                             end
    end

    def call
      validate_params

      ActiveRecord::Base.transaction do
        create_applied_credits
        mark_invoices_as_paid
      end

      Result.new(success?: true, record: nil, errors: [])
    rescue ValidationError => e
      Result.new(success?: false, record: nil, errors: [ e.message ])
    rescue StandardError => e
      Rails.logger.error("Error in ProcessPayment: #{e.message}")
      Result.new(success?: false, record: nil, errors: [ "Error al procesar el pago" ])
    end

    private

    class ValidationError < StandardError; end

    def validate_params
      raise ValidationError, "Debe haber al menos una factura para pagar" if @invoices.empty?

      @invoices.each { |invoice| validate_invoice(invoice) }

      validate_same_supplier
      validate_credit_applications if @credit_applications.any?
    end

    def validate_invoice(invoice)
      unless invoice.simple_mode?
        raise ValidationError, "Solo facturas en modo simple pueden marcarse como pagadas (ID: #{invoice.id})"
      end

      if invoice.paid_status?
        raise ValidationError, "La factura #{invoice.invoice_number} ya está pagada"
      end

      if @payment_date < invoice.purchase_date
        raise ValidationError, "La fecha de pago no puede ser anterior a la fecha de la factura #{invoice.invoice_number}"
      end
    end

    def validate_same_supplier
      supplier_ids = @invoices.map(&:supplier_id).uniq
      raise ValidationError, "Todas las facturas deben ser del mismo proveedor" if supplier_ids.size > 1
    end

    def validate_credit_applications
      invoice_ids = @invoices.map(&:id)

      # Track remaining balance per credit note within this payment (multiple applications of same NC)
      balance_consumed = Hash.new(0)

      @credit_applications.each do |app|
        credit_note = CreditNote.find_by(id: app[:credit_note_id])

        raise ValidationError, "Nota de crédito no encontrada (ID: #{app[:credit_note_id]})" unless credit_note
        raise ValidationError, "La nota de crédito #{credit_note.credit_note_number} no está disponible" unless credit_note.active_status?

        supplier_id = @invoices.first.supplier_id
        unless credit_note.supplier_id == supplier_id
          raise ValidationError, "La nota de crédito #{credit_note.credit_note_number} pertenece a otro proveedor"
        end

        unless invoice_ids.include?(app[:invoice_id])
          raise ValidationError, "La factura (ID: #{app[:invoice_id]}) no está en la lista de facturas a pagar"
        end

        raise ValidationError, "El monto a aplicar debe ser mayor a 0" unless app[:amount].to_d > 0

        already_applied   = credit_note.applied_credits.sum(:amount)
        in_this_payment   = balance_consumed[credit_note.id]
        available         = credit_note.amount - already_applied - in_this_payment

        if app[:amount].to_d > available
          raise ValidationError,
                "El monto aplicado de #{credit_note.credit_note_number} (#{app[:amount]}) " \
                "supera el saldo disponible (#{available})"
        end

        balance_consumed[credit_note.id] += app[:amount].to_d
      end
    end

    def create_applied_credits
      @credit_applications.each do |app|
        AppliedCredit.create!(
          credit_note_id: app[:credit_note_id],
          invoice_id:     app[:invoice_id],
          amount:         app[:amount].to_d,
          applied_at:     @payment_date
        )
      end
    end

    def mark_invoices_as_paid
      @invoices.each do |invoice|
        invoice.mark_as_paid!(@payment_date, paid_with_discount: invoice.eligible_for_discount?(@payment_date))
      end
    end

    # Distributes selected credit notes across invoices in order using their full remaining balance.
    # Returns [{credit_note_id:, invoice_id:, amount:}].
    def distribute_credits(credit_note_ids)
      return [] if credit_note_ids.empty?

      distributed = []

      nc_data = CreditNote.where(id: credit_note_ids).map do |cn|
        { cn: cn, remaining: cn.remaining_balance.to_d }
      end

      @invoices.each do |invoice|
        invoice_ceiling   = invoice.eligible_for_discount?(@payment_date) ? invoice.amount_with_discount : invoice.amount
        invoice_remaining = invoice_ceiling.to_d

        nc_data.each do |data|
          break if invoice_remaining <= 0
          next if data[:remaining] <= 0

          amount = [ data[:remaining], invoice_remaining ].min.round(2)

          distributed << { credit_note_id: data[:cn].id, invoice_id: invoice.id, amount: amount }
          data[:remaining]  -= amount
          invoice_remaining -= amount
        end
      end

      distributed
    end
  end
end
