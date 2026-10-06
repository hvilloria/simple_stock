# frozen_string_literal: true

class AddExpenseTypesToSuppliers < ActiveRecord::Migration[7.2]
  def change
    add_column :suppliers, :expense_types, :string, array: true, null: false, default: [ "supplier" ]
  end
end
