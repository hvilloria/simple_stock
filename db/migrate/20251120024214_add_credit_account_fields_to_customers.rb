class AddCreditAccountFieldsToCustomers < ActiveRecord::Migration[7.2]
  def change
    add_column :customers, :has_credit_account, :boolean, default: false, null: false
    add_column :customers, :customer_type, :string, default: 'retail', null: false
  end
end
