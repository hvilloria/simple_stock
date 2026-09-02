# frozen_string_literal: true

module Cash
  # The single strict reading of a money amount for the cash module.
  #
  # Only accepts values that are already numeric or a plain decimal string. An
  # AR-formatted string like "1.500.000,50" or "101.800" is rejected rather than
  # run through BigDecimal, which would silently return 1.5 and 101.8.
  module AmountParser
    PLAIN_DECIMAL = /\A-?\d+(\.\d{1,2})?\z/

    module_function

    # Returns a BigDecimal, or nil when the value is not a trustworthy amount.
    def parse(value)
      case value
      when Numeric then BigDecimal(value.to_s)
      when String  then decimal_from(value)
      end
    end

    def decimal_from(string)
      return nil unless string.match?(PLAIN_DECIMAL)

      BigDecimal(string)
    end
  end
end
