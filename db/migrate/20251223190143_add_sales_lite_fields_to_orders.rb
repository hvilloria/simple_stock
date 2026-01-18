class AddSalesLiteFieldsToOrders < ActiveRecord::Migration[7.2]
  def change
    # Campos para ventas-lite
    add_column :orders, :source, :string, default: 'live', null: false
    add_column :orders, :sale_date, :date, null: false, default: -> { 'CURRENT_DATE' }
    add_column :orders, :paper_number, :string

    # Índices
    add_index :orders, :source
    add_index :orders, :sale_date
    add_index :orders, :paper_number

    # Permitir unit_price NULL en order_items
    change_column_null :order_items, :unit_price, true

    # Backfill: orders existentes son 'live' y tienen sale_date = created_at
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE orders#{' '}
          SET sale_date = DATE(created_at)
          WHERE sale_date IS NULL
        SQL
      end
    end
  end
end
