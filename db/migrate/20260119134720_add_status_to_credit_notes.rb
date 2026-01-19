class AddStatusToCreditNotes < ActiveRecord::Migration[7.2]
  def change
    add_column :credit_notes, :status, :string, default: "pending", null: false
    add_column :credit_notes, :applied_at, :date
    add_index :credit_notes, :status
  end
end
