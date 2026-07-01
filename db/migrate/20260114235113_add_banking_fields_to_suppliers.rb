class AddBankingFieldsToSuppliers < ActiveRecord::Migration[7.2]
  def change
    # Add banking fields and payment term
    add_column :suppliers, :cuit, :string
    add_column :suppliers, :bank_alias, :string
    add_column :suppliers, :bank_account, :string
    add_column :suppliers, :payment_term_days, :integer

    # Add a unique index on name
    add_index :suppliers, :name, unique: true

    # Remove fields we don't use
    remove_column :suppliers, :contact_name, :string
    remove_column :suppliers, :address, :text
    remove_column :suppliers, :notes, :text
  end
end
