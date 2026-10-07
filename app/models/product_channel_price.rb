# frozen_string_literal: true

class ProductChannelPrice < ApplicationRecord
  CHANNELS = %w[mercadolibre].freeze
  LABELS = { "mercadolibre" => "Mercado Libre" }.freeze

  belongs_to :product

  validates :channel, inclusion: { in: CHANNELS }, uniqueness: { scope: :product_id }
  validate :price_positive

  def self.own_price?(channel)
    CHANNELS.include?(channel.to_s)
  end

  def self.label(channel)
    LABELS.fetch(channel.to_s, channel.to_s)
  end

  private

  def price_positive
    return if price.present? && price.positive?

    errors.add(:base, "Precio #{self.class.label(channel)} debe ser mayor a 0")
  end
end
