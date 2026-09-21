# frozen_string_literal: true

module Cash
  # Closes a business date: records the counting difference, wraps the counted
  # cash into the bundles, seals every movement of the date and persists the
  # closing record — in that order, so the drawer ends the day on exactly zero
  # and the rows written here are sealed too.
  #
  # There is no reopening: a date with a closing is refused. Neither is a date
  # that has not come yet; a past date left open can still be closed.
  class CloseDay
    TRANSFER_DESCRIPTION = "Cierre de caja del día"

    def self.call(**params)
      new(**params).call
    end

    def initialize(business_date:, counted_cash:, user:,
                   payway_batch_total: nil, mercado_pago_total: nil, note: nil)
      @business_date      = business_date
      @counted_cash       = counted_cash
      @user               = user
      @payway_batch_total = payway_batch_total
      @mercado_pago_total = mercado_pago_total
      @note               = note
    end

    def call
      validate!

      closing = nil
      ActiveRecord::Base.transaction do
        # Created first so the movements written below can be sealed in the
        # same pass as the ones already on the date. expected_cash is read
        # before any write, so the discrepancy cannot pollute it.
        closing = create_closing!
        record_discrepancy!
        record_transfer!
        seal_movements!(closing)
      end

      Result.new(success?: true, record: closing, errors: [])
    rescue ValidationError => e
      Result.new(success?: false, record: nil, errors: [ e.message ])
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, record: nil, errors: e.record.errors.full_messages)
    rescue StandardError => e
      Rails.logger.error("Error in Cash::CloseDay: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      Result.new(success?: false, record: nil, errors: [ "Error cerrando el día" ])
    end

    private

    class ValidationError < StandardError; end

    def validate!
      raise ValidationError, "El usuario es obligatorio" if @user.blank?
      raise ValidationError, "La fecha es obligatoria" if @business_date.blank?
      if counted.nil? || counted.negative?
        raise ValidationError, "El monto contado debe ser un número mayor o igual a cero"
      end
      raise ValidationError, "El total de Payway no es un monto válido" if invalid_optional?(@payway_batch_total)
      raise ValidationError, "El total de Mercado Pago no es un monto válido" if invalid_optional?(@mercado_pago_total)
      if @business_date.to_date > Date.current
        raise ValidationError, "El día #{I18n.l(@business_date.to_date)} todavía no llegó: no se puede cerrar por adelantado"
      end
      if DailyClosing.exists?(business_date: @business_date)
        raise ValidationError, "El día #{I18n.l(@business_date.to_date)} ya fue cerrado"
      end
    end

    def create_closing!
      DailyClosing.create!(
        business_date:      @business_date,
        expected_cash:      expected,
        counted_cash:       counted,
        payway_batch_total: payway_batch_total,
        mercado_pago_total: mercado_pago_total,
        closed_at:          Time.current,
        user:               @user
      )
    end

    def record_discrepancy!
      return if difference.zero?

      unwrap!(
        RecordMovement.call(
          business_date: @business_date,
          account:       "drawer",
          amount:        difference,
          category:      "cash_discrepancy",
          description:   @note,
          user:          @user
        )
      )
    end

    def record_transfer!
      return unless counted.positive?

      unwrap!(
        RecordTransfer.call(
          from:          "drawer",
          to:            "main_cash",
          amount:        counted,
          business_date: @business_date,
          user:          @user,
          description:   TRANSFER_DESCRIPTION
        )
      )
    end

    # update_all would skip the immutability guard and happily re-seal a row
    # another closing owns, so each row is stamped one at a time.
    def seal_movements!(closing)
      CashMovement.on(@business_date).where(daily_closing_id: nil).find_each do |movement|
        movement.update!(daily_closing_id: closing.id)
      end
    end

    def unwrap!(result)
      raise ValidationError, result.errors.to_sentence if result.failure?
    end

    def difference
      return @difference if defined?(@difference)

      @difference = counted - expected
    end

    # Read before anything is written, so the discrepancy row this service
    # creates never feeds back into the expectation it was derived from.
    def expected
      return @expected if defined?(@expected)

      @expected = CashMovement.drawer_balance_on(@business_date)
    end

    def counted
      return @counted if defined?(@counted)

      @counted = AmountParser.parse(@counted_cash)
    end

    def payway_batch_total
      @payway_batch_total.presence && AmountParser.parse(@payway_batch_total)
    end

    def mercado_pago_total
      @mercado_pago_total.presence && AmountParser.parse(@mercado_pago_total)
    end

    def invalid_optional?(value)
      value.present? && AmountParser.parse(value).nil?
    end
  end
end
