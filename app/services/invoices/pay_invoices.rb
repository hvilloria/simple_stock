# frozen_string_literal: true

module Invoices
  # Pays one or more pending invoices of one supplier and one type: applies the
  # chosen credit notes, takes the net out of an arca as a single outflow, and
  # marks every invoice paid pointing at that row. All or nothing.
  class PayInvoices
    ACCOUNTS = %w[drawer main_cash bank mercado_pago].freeze

    def self.call(**params)
      new(**params).call
    end

    def initialize(invoices:, account:, payment_date:, user:, credit_note_ids: [])
      @invoice_ids     = Array(invoices).map { |invoice| invoice.respond_to?(:id) ? invoice.id : invoice }
      @account         = account.to_s
      @payment_date    = payment_date
      @user            = user
      @credit_note_ids = Array(credit_note_ids).map(&:to_i).reject(&:zero?)
    end

    def call
      movement = nil

      ActiveRecord::Base.transaction do
        raise ValidationError, "Debe haber al menos una factura para pagar" if @invoice_ids.empty?

        # Locked so a double submit waits here and then sees the invoices paid.
        @invoices = Invoice.where(id: @invoice_ids).includes(:supplier).order(:id).lock.to_a
        validate!

        applied = apply_credits
        movement = record_outflow(net_amount(applied))

        @invoices.each do |invoice|
          invoice.cash_movement = movement
          invoice.mark_as_paid!(@payment_date, paid_with_discount: invoice.eligible_for_discount?(@payment_date))
        end
      end

      Result.new(success?: true, record: movement, errors: [])
    rescue ValidationError => e
      Result.new(success?: false, record: nil, errors: [ e.message ])
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, record: nil, errors: e.record.errors.full_messages)
    rescue StandardError => e
      Rails.logger.error("Error in Invoices::PayInvoices: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      Result.new(success?: false, record: nil, errors: [ "Error al registrar el pago" ])
    end

    private

    class ValidationError < StandardError; end

    def validate!
      raise ValidationError, "Debe haber al menos una factura para pagar" if @invoices.empty?
      raise ValidationError, "Elegí de dónde sale la plata" unless ACCOUNTS.include?(@account)
      raise ValidationError, "La fecha de pago es obligatoria" if @payment_date.nil?
      raise ValidationError, "La fecha de pago no puede ser futura" if @payment_date > Date.current

      if DailyClosing.exists?(business_date: @payment_date)
        raise ValidationError, "El día #{@payment_date.strftime('%d/%m/%Y')} está cerrado. Usá una fecha abierta."
      end

      @invoices.each { |invoice| validate_invoice(invoice) }

      if @invoices.map(&:supplier_id).uniq.size > 1
        raise ValidationError, "Todas las facturas deben ser del mismo proveedor"
      end
      if @invoices.map(&:expense_type).uniq.size > 1
        raise ValidationError, "Pagá por separado las facturas de distinto tipo"
      end

      validate_credit_notes if @credit_note_ids.any?
    end

    def validate_invoice(invoice)
      unless invoice.simple_mode?
        raise ValidationError, "Solo facturas en modo simple pueden pagarse (#{invoice.reference})"
      end
      raise ValidationError, "La factura #{invoice.reference} ya está pagada" if invoice.paid_status?
      raise ValidationError, "La factura #{invoice.reference} no está pendiente" unless invoice.pending_status?
      if @payment_date < invoice.purchase_date
        raise ValidationError, "La fecha de pago no puede ser anterior a la fecha de la factura #{invoice.reference}"
      end
    end

    def validate_credit_notes
      unless @invoices.first.supplier_expense_type?
        raise ValidationError, "Las notas de crédito solo se aplican a facturas de proveedor"
      end

      credit_notes.each do |credit_note|
        raise ValidationError, "La nota de crédito #{credit_note.credit_note_number} no está disponible" unless credit_note.available?
        if credit_note.supplier_id != @invoices.first.supplier_id
          raise ValidationError, "La nota de crédito #{credit_note.credit_note_number} pertenece a otro proveedor"
        end
      end
      raise ValidationError, "Nota de crédito no encontrada" if credit_notes.size != @credit_note_ids.uniq.size
    end

    def credit_notes
      @credit_notes ||= CreditNote.where(id: @credit_note_ids).order(:id).lock.to_a
    end

    # Spends each selected note's balance across the invoices in order, never
    # past what an invoice still owes in pesos on the payment date. Notes are
    # tracked and stored in their own currency; the invoice and the outflow
    # are reduced by the peso value that was applied.
    def apply_credits
      return BigDecimal("0") if @credit_note_ids.empty?

      balances = credit_notes.to_h { |credit_note| [ credit_note, credit_note.remaining_balance.to_d ] }
      applied_total = BigDecimal("0")

      @invoices.each do |invoice|
        owed = invoice.amount_due_ars(@payment_date)

        balances.each do |credit_note, remaining|
          break if owed <= 0

          rate = credit_note_rate(credit_note)
          native = [ remaining, (owed / rate).round(2, BigDecimal::ROUND_CEILING) ].min
          next if native <= 0

          pesos = [ (native * rate).round(2), owed ].min
          AppliedCredit.create!(credit_note: credit_note, invoice: invoice, amount: native, applied_at: @payment_date)
          balances[credit_note] -= native
          owed -= pesos
          applied_total += pesos
        end
      end

      applied_total
    end

    def credit_note_rate(credit_note)
      credit_note.currency == "USD" ? credit_note.exchange_rate.to_d : BigDecimal("1")
    end

    def net_amount(applied)
      (@invoices.sum { |invoice| invoice.amount_due_ars(@payment_date) } - applied).round(2)
    end

    def record_outflow(net)
      return nil unless net.positive?

      result = Cash::RecordMovement.call(
        business_date: @payment_date,
        account: @account,
        amount: -net,
        user: @user,
        description: description,
        **@invoices.first.cash_category_attrs
      )
      raise ValidationError, result.errors.join(", ") if result.failure?

      result.record
    end

    def description
      "Pago #{@invoices.first.supplier.name} — #{@invoices.map(&:reference).join(', ')}"
    end
  end
end
