class AddSalesLiteFieldsToOrders < ActiveRecord::Migration[7.2]
  def change
    # Fields for sales-lite
    add_column :orders, :source, :string, default: 'live', null: false
    add_column :orders, :sale_date, :date, null: false, default: -> { 'CURRENT_DATE' }
    add_column :orders, :paper_number, :string

    # Indexes
    add_index :orders, :source
    add_index :orders, :sale_date
    add_index :orders, :paper_number

    # Allow unit_price NULL in order_items
    change_column_null :order_items, :unit_price, true

    # Backfill: existing orders are 'live' and have sale_date = created_at
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
