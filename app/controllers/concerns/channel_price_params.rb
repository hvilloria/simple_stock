# frozen_string_literal: true

# Reads the per-channel price fields (channel_prices[<channel>]) shared by the
# product and combo forms.
module ChannelPriceParams
  extend ActiveSupport::Concern
  include CurrencyParser

  private

  # Blank means remove the channel price; anything else is parsed, so
  # garbage reads as 0 and the model refuses it.
  def parsed_channel_prices
    return {} unless channel_prices_hash?

    submitted_channel_price_values.transform_values { |raw| raw.blank? ? nil : parse_amount(raw) }
  end

  def channel_prices_hash?
    !params.key?(:channel_prices) || params[:channel_prices].is_a?(ActionController::Parameters)
  end

  def submitted_channel_price_values
    return ProductChannelPrice::CHANNELS.index_with { "" } unless channel_prices_hash?

    raw = params.fetch(:channel_prices, {}).permit(*ProductChannelPrice::CHANNELS).to_h
    ProductChannelPrice::CHANNELS.index_with { |channel| raw[channel].to_s }
  end

  # Re-render values: a positive price is shown AR-formatted (the form's own
  # cleanup leaves dots that a later unformat would misread); anything else
  # is echoed as typed.
  def echoed_channel_price_values
    submitted_channel_price_values.to_h do |channel, raw|
      amount = parse_amount(raw)
      [ channel, amount&.positive? ? format_channel_price(amount) : raw ]
    end
  end

  def format_channel_price(amount)
    helpers.number_with_precision(amount, precision: 2, delimiter: ".", separator: ",")
  end

  def channel_price_values_for(product)
    ProductChannelPrice::CHANNELS.index_with do |channel|
      price = product.channel_price_for(channel)&.price
      price ? format_channel_price(price) : ""
    end
  end
end
