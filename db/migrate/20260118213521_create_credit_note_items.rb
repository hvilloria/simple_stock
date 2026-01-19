class CreateCreditNoteItems < ActiveRecord::Migration[7.2]
  def change
    create_table :credit_note_items do |t|
      t.references :credit_note, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: true
      t.integer :quantity, null: false
      t.decimal :unit_price, precision: 10, scale: 2, null: false

      t.timestamps
    end
  end
end
