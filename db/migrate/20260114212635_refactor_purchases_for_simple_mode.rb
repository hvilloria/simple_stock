class RefactorPurchasesForSimpleMode < ActiveRecord::Migration[7.2]
  def change
    # Agregar campos para modo simple
    add_column :purchases, :invoice_number, :string
    add_column :purchases, :due_date, :date
    add_column :purchases, :paid_at, :datetime
    add_column :purchases, :has_items, :boolean, default: false, null: false
    add_column :purchases, :amount, :decimal, precision: 10, scale: 2
    
    # Hacer total_cost opcional (cuando has_items=false, usar amount)
    change_column_null :purchases, :total_cost, true
    
    # Índices
    add_index :purchases, :invoice_number
    add_index :purchases, :due_date
    add_index :purchases, :has_items
    add_index :purchases, :paid_at
    
    # Migración de datos: purchases existentes son modo completo
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE purchases 
          SET has_items = true 
          WHERE id IS NOT NULL
        SQL
      end
    end
  end
end
