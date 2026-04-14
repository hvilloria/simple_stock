# frozen_string_literal: true

class CreateSalesImports < ActiveRecord::Migration[7.2]
  def change
    create_table :sales_imports do |t|
      t.string  :source_filename,        null: false
      t.string  :status,                 null: false, default: "pending"
      t.datetime :imported_at
      t.integer :rows_count,             null: false, default: 0
      t.integer :created_products_count, null: false, default: 0
      t.integer :created_entries_count,  null: false, default: 0
      t.integer :failed_rows_count,      null: false, default: 0
      t.text    :notes
      t.timestamps
    end

    add_index :sales_imports, :status
    add_index :sales_imports, :imported_at
  end
end
