# frozen_string_literal: true

module Cash
  # Undoes a collection by writing its mirror image: the same amount with the
  # opposite sign, same arca, same channel and the same source_payment_id. The
  # original row is never edited or deleted, so this works the same whether its
  # day is open or already sealed. The reversal is dated when it happens, not
  # when the collection did.
  class ReversePayment
    def self.call(**params)
      new(**params).call
    end

    def initialize(payment:, user:, business_date: Date.current)
      @payment       = payment
      @user          = user
      @business_date = business_date
    end

    def call
      validate!

      RecordMovement.call(
        business_date:  @business_date,
        account:        original.account,
        amount:         -original.amount,
        category:       original.category,
        channel:        original.channel,
        description:    reversal_description,
        source_payment: @payment,
        user:           @user
      )
    rescue ValidationError => e
      failure(e.message)
    rescue StandardError => e
      Rails.logger.error("Error in Cash::ReversePayment: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      failure("Error revirtiendo el cobro en caja")
    end

    private

    class ValidationError < StandardError; end

    def validate!
      raise ValidationError, "El pago es obligatorio" if @payment.blank?
      raise ValidationError, "El usuario es obligatorio" if @user.blank?
      raise ValidationError, "Este cobro no tiene movimiento de caja" if movements.empty?
      # The original and its reversal share a source_payment_id: a second row is
      # the reversal, and there is nothing left to undo.
      raise ValidationError, "Este cobro ya fue revertido" if movements.size > 1
    end

    def movements
      @movements ||= CashMovement.where(source_payment_id: @payment.id).order(:id).to_a
    end

    def original
      movements.first
    end

    def reversal_description
      "Reversa del cobro ##{@payment.id} del #{original.business_date.strftime('%d/%m/%Y')}"
    end

    def failure(message)
      Result.new(success?: false, record: nil, errors: [ message ])
    end
  end
end
