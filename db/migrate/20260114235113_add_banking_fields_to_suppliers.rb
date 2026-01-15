class AddBankingFieldsToSuppliers < ActiveRecord::Migration[7.2]
  def change
    # Agregar campos bancarios y plazo de pago
    add_column :suppliers, :cuit, :string
    add_column :suppliers, :bank_alias, :string
    add_column :suppliers, :bank_account, :string
    add_column :suppliers, :payment_term_days, :integer

    # Agregar índice unique en name
    add_index :suppliers, :name, unique: true

    # Eliminar campos que no usamos
    remove_column :suppliers, :contact_name, :string
    remove_column :suppliers, :address, :text
    remove_column :suppliers, :notes, :text
  end
end
