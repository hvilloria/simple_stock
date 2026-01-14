# frozen_string_literal: true

class DeviseCreateUsers < ActiveRecord::Migration[7.2]
  def change
    create_table :users do |t|
      ## Database authenticatable
      t.string :email,              null: false, default: ""
      t.string :encrypted_password, null: false, default: ""

      ## Trackable
      t.datetime :current_sign_in_at
      t.datetime :last_sign_in_at
      t.string   :current_sign_in_ip
      t.string   :last_sign_in_ip
      t.integer  :sign_in_count, default: 0, null: false

      ## Custom fields
      t.string :name, null: false
      t.string :role, default: "vendedor", null: false

      t.timestamps null: false
    end

    add_index :users, :email, unique: true
    add_index :users, :role
  end
end
