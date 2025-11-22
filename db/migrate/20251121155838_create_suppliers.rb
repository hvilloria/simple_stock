class CreateSuppliers < ActiveRecord::Migration[7.2]
  def change
    create_table :suppliers do |t|
      t.string :name, null: false
      t.string :contact_name
      t.string :phone
      t.string :email
      t.text :address
      t.text :notes

      t.timestamps
    end
  end
end
