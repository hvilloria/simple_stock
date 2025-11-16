class CreateCustomers < ActiveRecord::Migration[7.2]
  def change
    create_table :customers do |t|
      t.string :name, null: false
      t.string :document
      t.string :phone

      t.timestamps
    end

    add_index :customers, :document
  end
end
