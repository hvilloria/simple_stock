# frozen_string_literal: true

module Products
  # Saves a product with its per-channel prices in one transaction. A nil
  # channel price removes that channel's own price.
  class Save
    def self.call(product:, attributes:, channel_prices: {})
      new(product: product, attributes: attributes, channel_prices: channel_prices).call
    end

    def initialize(product:, attributes:, channel_prices:)
      @product        = product
      @attributes     = attributes
      @channel_prices = channel_prices.to_h.select { |channel, _| ProductChannelPrice.own_price?(channel) }
    end

    def call
      ActiveRecord::Base.transaction do
        @product.assign_attributes(@attributes)
        @product.save!
        @channel_prices.each { |channel, price| apply(channel.to_s, price) }
      end

      Result.new(success?: true, record: @product, errors: [])
    rescue ActiveRecord::RecordInvalid => e
      messages = e.record.errors.full_messages
      messages.each { |message| @product.errors.add(:base, message) } unless e.record.equal?(@product)
      Result.new(success?: false, record: @product, errors: messages)
    end

    private

    def apply(channel, price)
      row = @product.channel_prices.find_or_initialize_by(channel: channel)

      if price.nil?
        row.destroy! if row.persisted?
      else
        row.update!(price: price)
      end
    end
  end
end
