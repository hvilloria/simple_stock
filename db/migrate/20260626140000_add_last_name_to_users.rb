class AddLastNameToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :last_name, :string
  end
end
