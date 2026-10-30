# frozen_string_literal: true

module Payments
  # Collects a partial, repeatable payment on an on_account sale.
  #
  # Caja enters what the customer hands over; the debt drops by that amount,
  # plus, with a cash-only discount, that percent of it rounded to the peso.
  # Cash equal to Order#cash_settle_amount settles the whole balance (what is
  # left to pay discounted, minus the discount already earned), and so does that
  # amount rounded down to the hundred when there is a discount; cash above it also
  # settles it and the excess is added to the total as overpaid, provided it
  # matches confirmed_overpaid, the excess the operator saw and confirmed.
  # The discount lowers total_amount; the allocation records the cash received
  # and how much of the sale it covered (all that was left, when it settles).
  class CollectOnAccount
    ALLOWED_DISCOUNTS = [ 0, 5, 10 ].freeze
    TOLERANCE = 0.01
    BALANCE_CHANGED = "El saldo cambió durante el cobro. Revisar el monto."

    def self.call(order:, tenders:, user:, discount_percent: 0, payment_date: Date.current, confirmed_overpaid: 0)
      new(
        order: order,
        tenders: tenders,
        user: user,
        discount_percent: discount_percent,
        payment_date: payment_date,
        confirmed_overpaid: confirmed_overpaid
      ).call
    end

    def initialize(order:, tenders:, user:, discount_percent:, payment_date:, confirmed_overpaid:)
      @order              = order
      @user               = user
      @tenders            = Array(tenders).map { |t| t.to_h.symbolize_keys }
      @discount_percent   = discount_percent.to_i
      @payment_date       = payment_date || Date.current
      @confirmed_overpaid = confirmed_overpaid.to_d
    end

    def call
      validate!
      covered = covered_by_method

      ActiveRecord::Base.transaction do
        apply_totals!
        create_payments_and_allocations!(covered)
        @order.refresh_status_from_balance!

        Result.new(success?: true, record: @order, errors: [])
      end
    rescue ValidationError => e
      Result.new(success?: false, record: nil, errors: [ e.message ])
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, record: nil, errors: e.record.errors.full_messages)
    rescue StandardError => e
      Rails.logger.error("Error in Payments::CollectOnAccount: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      Result.new(success?: false, record: nil, errors: [ "Error registrando el cobro" ])
    end

    private

    class ValidationError < StandardError; end

    def validate!
      unless @order.on_account_order_type? && !@order.cancelled_status?
        raise ValidationError, "La operación no es un pago a cuenta activo"
      end

      raise ValidationError, "La operación ya está saldada" unless balance.positive?

      unless ALLOWED_DISCOUNTS.include?(@discount_percent)
        raise ValidationError, "Descuento inválido (0, 5 o 10)"
      end

      raise ValidationError, "Debe incluir al menos un pago" if @tenders.empty?

      @tenders.each do |t|
        raise ValidationError, "El monto debe ser mayor a cero" unless t[:amount].to_d.positive?
        raise ValidationError, Payment::MISSING_METHOD_ERROR if t[:payment_method].blank?
        unless Payment::PAYMENT_METHODS.include?(t[:payment_method])
          raise ValidationError, "Método de pago inválido: #{t[:payment_method]}"
        end
      end

      @tenders.group_by { |t| t[:payment_method] }.each do |method, rows|
        next if rows.map { |r| invoice_of(r) }.uniq.one?

        raise ValidationError, "Las filas de #{Payment.method_label(method)} tienen facturas distintas"
      end

      if @discount_percent.positive? && @tenders.any? { |t| t[:payment_method] != "cash" }
        raise ValidationError, "Descuento solo permitido si el cobro es en efectivo"
      end

      raise ValidationError, excess_message if settled > balance
      raise ValidationError, BALANCE_CHANGED if overpaid.positive? && (overpaid - @confirmed_overpaid).abs > TOLERANCE
    end

    def received
      @received ||= @tenders.sum { |t| t[:amount].to_d }
    end

    def balance
      @balance ||= @order.outstanding_balance
    end

    def cash_received
      @tenders.select { |t| t[:payment_method] == "cash" }.sum { |t| t[:amount].to_d }
    end

    def settle_all_cash
      @settle_all_cash ||= @order.cash_settle_amount(@discount_percent)
    end

    def overpaid
      @overpaid ||= begin
        extra = received - settle_all_cash
        extra.positive? && extra <= cash_received ? extra : 0
      end
    end

    def settles_all?
      received == settle_all_cash || overpaid.positive? || rounded_down?
    end

    # With a cash discount the settling cash may be rounded down to the hundred.
    def rounded_down?
      return false unless @discount_percent.positive?

      floor = (settle_all_cash / 100).floor * 100
      floor.positive? && received >= floor && received < settle_all_cash
    end

    # What this collection takes off the debt.
    def settled
      @settled ||=
        if settles_all? then balance
        elsif @discount_percent.zero? then received
        else received + (received * @discount_percent / 100).round(0)
        end
    end

    def discount
      settled - received + overpaid
    end

    def excess_message
      amount = ActiveSupport::NumberHelper.number_to_currency(
        settle_all_cash, unit: "$ ", separator: ",", delimiter: ".", precision: 2
      )
      with = @discount_percent.positive? ? " con #{@discount_percent}%" : ""
      "Es más de lo que debe. Para saldar todo#{with} corresponde cobrar #{amount}"
    end

    def apply_totals!
      return if discount.zero? && overpaid.zero?

      @order.update!(total_amount: @order.total_amount - discount + overpaid)
    end

    def received_by_method
      @received_by_method ||= @tenders.group_by { |t| t[:payment_method] }
                                      .transform_values { |rows| rows.sum { |r| r[:amount].to_d } }
    end

    # A settling collection covers all that was left; the cash allocation (else
    # the first one) carries the discounts earlier collections had earned.
    def covered_by_method
      covered = received_by_method.dup
      return covered unless settles_all?

      carrier = covered.key?("cash") ? "cash" : covered.keys.first
      covered[carrier] = @order.remaining_to_pay - (received - covered[carrier])
      covered
    end

    def create_payments_and_allocations!(covered)
      received_by_method.each do |method, total|
        payment = Payment.create!(
          customer:       @order.customer,
          amount:         total,
          payment_method: method,
          payment_date:   @payment_date
        )
        assign_invoice!(payment, @tenders.find { |t| t[:payment_method] == method })
        # One allocation per method: payment_allocations is unique on
        # (payment_id, order_id), so repeated rows of the same method collapse.
        # A discount only exists on an all-cash collection, so it lands here,
        # and overpaid cash is always on the cash allocation.
        PaymentAllocation.create!(payment: payment, order: @order, amount: total,
                                  covered_amount: covered[method],
                                  discount_amount: method == "cash" ? discount : 0,
                                  overpaid_amount: method == "cash" ? overpaid : 0)

        record_in_cash!(payment)
      end
    end

    def record_in_cash!(payment)
      result = Cash::RecordSaleFromPayment.call(
        payment:     payment,
        user:        @user,
        description: cash_description
      )

      raise ValidationError, result.errors.join(", ") if result.failure?
    end

    def assign_invoice!(payment, row)
      invoice_type, invoice_number = invoice_of(row)
      return if invoice_type.nil?

      result = Payments::AssignInvoice.call(payment: payment, invoice_type: invoice_type,
                                            invoice_number: invoice_number)
      raise ValidationError, result.errors.join(", ") if result.failure?
    end

    # The number only counts for A and B, so a stray one on "none" does not
    # make two rows of the same method disagree.
    def invoice_of(row)
      invoice_type = row[:invoice_type].presence
      number = row[:invoice_number].to_s.strip.presence if %w[a b].include?(invoice_type)
      [ invoice_type, number ]
    end

    def cash_description
      @cash_description ||= [
        "Cobro a cuenta",
        ("Nota #{@order.paper_number}" if @order.paper_number.present?),
        @order.contact_name.presence
      ].compact.join(" — ")
    end
  end
end
