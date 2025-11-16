module Inventory
  class CalculateStockLevel
    def self.call(product:)
      new(product:).call
    end

    def initialize(product:)
      @product = product
    end

    def call
      @product.current_stock
    end
  end
end
