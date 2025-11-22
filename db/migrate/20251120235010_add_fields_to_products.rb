class AddFieldsToProducts < ActiveRecord::Migration[7.2]
  def change
    add_column :products, :cost_currency, :string, default: 'ARS', null: false
    add_column :products, :origin, :string
    add_column :products, :product_type, :string
    add_column :products, :brand, :string
  end
end
