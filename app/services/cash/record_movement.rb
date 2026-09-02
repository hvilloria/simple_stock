# frozen_string_literal: true

module Cash
  # Records a single cash movement. Movements between arcas need two rows and
  # go through Cash::RecordTransfer instead.
  class RecordMovement
    def self.call(**params)
      new(**params).call
    end

    def initialize(business_date:, account:, amount:, category:, user:,
                   subcategory: nil, channel: nil, description: nil,
                   source_payment: nil)
      @business_date  = business_date
      @account        = account
      @amount         = amount
      @category       = category
      @user           = user
      @subcategory    = subcategory
      @channel        = channel
      @description    = description
      @source_payment = source_payment
    end

    def call
      validate!

      movement = CashMovement.create!(
        business_date:  @business_date,
        account:        @account,
        amount:         normalized_amount,
        category:       @category,
        subcategory:    @subcategory,
        channel:        @channel,
        description:    @description,
        source_payment: @source_payment,
        user:           @user
      )

      Result.new(success?: true, record: movement, errors: [])
    rescue ValidationError => e
      Result.new(success?: false, record: nil, errors: [ e.message ])
    rescue ArgumentError => e
      # Raised by ActiveRecord when an enum receives a value outside its set.
      Result.new(success?: false, record: nil, errors: [ e.message ])
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, record: nil, errors: e.record.errors.full_messages)
    rescue StandardError => e
      Rails.logger.error("Error in Cash::RecordMovement: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      Result.new(success?: false, record: nil, errors: [ "Error registrando el movimiento" ])
    end

    private

    class ValidationError < StandardError; end

    def validate!
      raise ValidationError, "El usuario es obligatorio" if @user.blank?
      raise ValidationError, "La fecha es obligatoria" if @business_date.blank?
      raise ValidationError, "El monto debe ser un número distinto de cero" if normalized_amount.nil?
      if @category.to_s == "internal_transfer"
        raise ValidationError, "Los movimientos entre arcas se registran de a dos legs"
      end
    end

    # Only accepts values that are already numeric or a plain decimal string.
    # An AR-formatted string like "1.500.000,50" or "101.800" is rejected rather
    # than run through BigDecimal, which would silently return 1.5 and 101.8.
    def normalized_amount
      return @normalized_amount if defined?(@normalized_amount)

      @normalized_amount =
        case @amount
        when Numeric then BigDecimal(@amount.to_s)
        when String  then decimal_from(@amount)
        end
    end

    def decimal_from(string)
      return nil unless string.match?(/\A-?\d+(\.\d{1,2})?\z/)

      BigDecimal(string)
    end
  end
end
