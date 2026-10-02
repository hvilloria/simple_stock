# frozen_string_literal: true

module Payments
  # Collects a partial, repeatable payment on an on_account sale.
  #
  # Caja enters what the customer hands over; the debt drops by that amount,
  # or, with a cash-only discount, by the amount grossed up by the discount and
  # rounded to the peso. Cash equal to the amount that settles the whole
  # balance (balance × (1 − discount), nearest hundred) settles it exactly.
  # The discount lowers total_amount; the allocation records the cash received.
  class CollectOnAccount
    include Payments::CashRounding

    ALLOWED_DISCOUNTS = [ 0, 5, 10 ].freeze

    def self.call(order:, tenders:, user:, discount_percent: 0, payment_date: Date.current)
      new(
        order: order,
        tenders: tenders,
        user: user,
        discount_percent: discount_percent,
        payment_date: payment_date
      ).call
    end

    def initialize(order:, tenders:, user:, discount_percent:, payment_date:)
      @order            = order
      @user             = user
      @tenders          = Array(tenders).map { |t| t.to_h.symbolize_keys }
      @discount_percent = discount_percent.to_i
      @payment_date     = payment_date || Date.current
    end

    def call
      validate!

      ActiveRecord::Base.transaction do
        apply_discount!
        create_payments_and_allocations!
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

      unless ALLOWED_DISCOUNTS.include?(@discount_percent)
        raise ValidationError, "Descuento inválido (0, 5 o 10)"
      end

      raise ValidationError, "Debe incluir al menos un pago" if @tenders.empty?

      @tenders.each do |t|
        raise ValidationError, "El monto debe ser mayor a cero" unless t[:amount].to_d.positive?
        unless Payment::PAYMENT_METHODS.include?(t[:payment_method])
          raise ValidationError, "Método de pago inválido: #{t[:payment_method]}"
        end
      end

      if @discount_percent.positive? && @tenders.any? { |t| t[:payment_method] != "cash" }
        raise ValidationError, "Descuento solo permitido si el cobro es en efectivo"
      end

      raise ValidationError, excess_message if settled > balance
    end

    def received
      @received ||= @tenders.sum { |t| t[:amount].to_d }
    end

    def balance
      @balance ||= @order.outstanding_balance
    end

    def factor
      1 - (@discount_percent.to_d / 100)
    end

    def settle_all_cash
      @settle_all_cash ||=
        if @discount_percent.positive?
          [ round_to_nearest_hundred(balance * factor), balance ].min
        else
          balance
        end
    end

    # What this collection takes off the debt.
    def settled
      @settled ||=
        if received == settle_all_cash then balance
        elsif @discount_percent.zero? then received
        else (received / factor).round(0)
        end
    end

    def discount
      settled - received
    end

    def excess_message
      amount = ActiveSupport::NumberHelper.number_to_currency(
        settle_all_cash, unit: "$ ", separator: ",", delimiter: ".", precision: 2
      )
      with = @discount_percent.positive? ? " con #{@discount_percent}%" : ""
      "Es más de lo que debe. Para saldar todo#{with} corresponde cobrar #{amount}"
    end

    def apply_discount!
      return if discount.zero?

      @order.update!(total_amount: @order.total_amount - discount)
    end

    def create_payments_and_allocations!
      @tenders.group_by { |t| t[:payment_method] }.each do |method, rows|
        total = rows.sum { |r| r[:amount].to_d }
        payment = Payment.create!(
          customer:       @order.customer,
          amount:         total,
          payment_method: method,
          payment_date:   @payment_date
        )
        # One allocation per method: payment_allocations is unique on
        # (payment_id, order_id), so repeated rows of the same method collapse.
        # A discount only exists on an all-cash collection, so it lands here.
        PaymentAllocation.create!(payment: payment, order: @order, amount: total,
                                  discount_amount: method == "cash" ? discount : 0)

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

    def cash_description
      @cash_description ||= [
        "Cobro a cuenta",
        ("Nota #{@order.paper_number}" if @order.paper_number.present?),
        @order.contact_name.presence
      ].compact.join(" — ")
    end
  end
end
