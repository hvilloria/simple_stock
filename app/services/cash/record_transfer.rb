# frozen_string_literal: true

module Cash
  # Moves money between two arcas by writing both legs of the transfer: the same
  # amount with opposite signs, tied together by a shared transfer_group_id.
  #
  # Two rows instead of one so that any arca's balance stays SUM(amount) WHERE
  # account = ?, with no conditions. The cost is paid once here, on write,
  # instead of on every balance read in the app.
  #
  # It does not go through Cash::RecordMovement: that service refuses the
  # internal_transfer category on purpose, because a one-legged transfer would
  # break the arca it never reached.
  class RecordTransfer
    def self.call(**params)
      new(**params).call
    end

    def initialize(from:, to:, amount:, business_date:, user:, description: nil)
      @from          = from
      @to            = to
      @amount        = amount
      @business_date = business_date
      @user          = user
      @description   = description
    end

    def call
      validate!

      movements = nil
      ActiveRecord::Base.transaction do
        movements = [ create_leg(@from, -normalized_amount), create_leg(@to, normalized_amount) ]
      end

      Result.new(success?: true, record: movements, errors: [])
    rescue ValidationError => e
      Result.new(success?: false, record: nil, errors: [ e.message ])
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, record: nil, errors: e.record.errors.full_messages)
    rescue StandardError => e
      Rails.logger.error("Error in Cash::RecordTransfer: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      Result.new(success?: false, record: nil, errors: [ "Error registrando el movimiento entre arcas" ])
    end

    private

    class ValidationError < StandardError; end

    def validate!
      raise ValidationError, "El usuario es obligatorio" if @user.blank?
      raise ValidationError, "La fecha es obligatoria" if @business_date.blank?
      raise ValidationError, "El arca de origen no existe" unless known_account?(@from)
      raise ValidationError, "El arca de destino no existe" unless known_account?(@to)
      raise ValidationError, "El origen y el destino deben ser arcas distintas" if @from.to_s == @to.to_s
      # The service assigns the signs; a negative amount is a caller mistake,
      # not a request to reverse the direction.
      if normalized_amount.nil? || !normalized_amount.positive?
        raise ValidationError, "El monto debe ser un número mayor a cero"
      end
    end

    def known_account?(account)
      CashMovement::ACCOUNT_LABELS.key?(account.to_s)
    end

    def create_leg(account, amount)
      CashMovement.create!(
        business_date:     @business_date,
        account:           account,
        amount:            amount,
        category:          "internal_transfer",
        description:       @description,
        transfer_group_id: transfer_group_id,
        user:              @user
      )
    end

    def transfer_group_id
      @transfer_group_id ||= SecureRandom.uuid
    end

    def normalized_amount
      return @normalized_amount if defined?(@normalized_amount)

      @normalized_amount = AmountParser.parse(@amount)
    end
  end
end
