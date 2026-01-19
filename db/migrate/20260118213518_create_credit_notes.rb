class CreateCreditNotes < ActiveRecord::Migration[7.2]
  def change
    create_table :credit_notes do |t|
      t.references :supplier, null: false, foreign_key: true
      t.references :invoice, null: true, foreign_key: true
      t.string :credit_note_number, null: false
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.string :currency, null: false, default: "ARS"
      t.decimal :exchange_rate, precision: 10, scale: 4
      t.date :issue_date, null: false
      t.text :notes

      t.timestamps
    end

    add_index :credit_notes, :credit_note_number, unique: true
    add_index :credit_notes, [ :supplier_id, :issue_date ]
  end
end
