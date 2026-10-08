# frozen_string_literal: true

class CreateProductChannelPrices < ActiveRecord::Migration[7.2]
  def change
    create_table :product_channel_prices do |t|
      t.references :product, null: false, foreign_key: true
      t.string :channel, null: false
      t.decimal :price, precision: 10, scale: 2, null: false
      t.timestamps
    end

    add_index :product_channel_prices, %i[product_id channel], unique: true
    add_check_constraint :product_channel_prices, "price > 0", name: "product_channel_prices_price_positive"
  end
end
